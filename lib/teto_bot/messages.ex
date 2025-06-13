defmodule TetoBot.Messages do
  @moduledoc """
  This module handles incoming messages for the TetoBot Discord bot, ensuring proper filtering, rate limiting,
  image processing, and response generation using a Large Language Model (LLM).
  It integrates with Nostrum for Discord API interactions and
  custom modules for additional functionality, such as user engagement tracking and rate limiting.
  """

  require Logger

  alias Nostrum.Api
  alias Nostrum.Bot
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct

  alias TetoBot.Accounts
  alias TetoBot.LLM
  alias TetoBot.Messages
  alias TetoBot.RateLimiting

  @spec handle_msg(Nostrum.Struct.Message.t()) :: :ok
  @doc """
  Handles an incoming Discord message, determining if it should be processed and executing the appropriate action.
  """
  def handle_msg(%Struct.Message{author: %Struct.User{bot: bot}} = msg) do
    my_bot_id = Bot.get_bot_name()

    msg
    |> should_process_message?(bot, my_bot_id)
    |> maybe_process_message(msg, my_bot_id)
  end

  # Skip all bot's messages, including other bots as well
  defp should_process_message?(_msg, bot, _my_bot_id) when bot == true,
    do: {:skip, :bot_message}

  defp should_process_message?(%Struct.Message{message_reference: nil}, _bot, _my_bot_id),
    do: {:process, :direct}

  defp should_process_message?(
         %Struct.Message{message_reference: %{message_id: replied_msg_id}},
         _bot,
         my_bot_id
       ) do
    case MessageCache.get(replied_msg_id) do
      {:ok, replied_to_msg} -> check_reply_target(replied_to_msg, my_bot_id, replied_msg_id)
      {:error, reason} -> {:error, reason, replied_msg_id}
    end
  end

  defp check_reply_target(replied_to_msg, my_bot_id, replied_msg_id) do
    cond do
      replied_to_msg.author.id == my_bot_id ->
        {:process, :reply_to_my_bot}

      replied_to_msg.author.bot ->
        {:skip, {:reply_to_other_bot, replied_msg_id}}

      true ->
        {:skip, {:reply_to_user, replied_msg_id}}
    end
  end

  defp maybe_process_message({:process, _reason}, msg, _bot_id), do: process_message(msg)
  defp maybe_process_message({:skip, :bot_message}, _msg, _bot_id), do: :ok

  defp maybe_process_message({:skip, {:reply_to_other_bot, replied_msg_id}}, _msg, _bot_id) do
    Logger.debug("Ignoring reply to other bot message: #{replied_msg_id}")
    :ok
  end

  defp maybe_process_message({:skip, {:reply_to_user, replied_msg_id}}, _msg, _bot_id) do
    Logger.debug("Ignoring reply to user message: #{replied_msg_id}")
    :ok
  end

  defp maybe_process_message({:error, reason, replied_msg_id}, _msg, _bot_id) do
    Logger.error("Failed to fetch replied message #{replied_msg_id}: #{inspect(reason)}")
    :ok
  end

  defp process_message(
         %Struct.Message{channel_id: channel_id, author: %Struct.User{id: user_id}} = msg
       ) do
    # Check both channel and user rate limits
    channel_allowed = RateLimiting.allow_channel?(channel_id)

    case RateLimiting.allow_user?(user_id) do
      {:ok, true} when channel_allowed ->
        generate_and_send_response!(msg)

      {:ok, true} ->
        send_rate_limit_warning(channel_id, :channel)
        :ok

      {:ok, false} ->
        send_user_rate_limit_warning(channel_id, user_id)
        :ok

      {:error, reason} ->
        Logger.error("Failed to check user rate limit for #{user_id}: #{inspect(reason)}")
        send_rate_limit_warning(channel_id, :error)
        :ok
    end
  end

  @spec generate_and_send_response!(Nostrum.Struct.Message.t()) :: :ok
  @doc false
  # Generates and sends a response using LLM, handling image attachments and updating metrics.
  defp generate_and_send_response!(msg) do
    %Struct.Message{
      author: %Struct.User{username: username, id: user_id},
      channel_id: channel_id,
      guild_id: guild_id,
      id: message_id
    } = msg

    Logger.info("Message received - User: #{username}(#{user_id}) from (Guild: #{guild_id})")
    Logger.debug("Message content: #{msg.content}")

    llm_response =
      msg.content
      |> Messages.Filter.contains_injection?()
      |> case do
        true ->
          msg
          |> build_message_context(guild_id, user_id, channel_id)
          |> generate_llm_response(:jailbreak)

        false ->
          msg
          |> Messages.Attachment.process_attachments()
          |> build_message_context(guild_id, user_id, channel_id)
          |> generate_llm_response(:standard)
      end

    llm_response
    |> send_discord_response(channel_id, message_id)
    |> update_user_metrics(guild_id, user_id)

    :ok
  end

  @doc false
  # Builds context map for LLM processing
  defp build_message_context(msg, guild_id, user_id, channel_id) do
    context = %{
      messages: TetoBot.MessageContext.get_context(channel_id),
      guild_id: guild_id,
      user_id: user_id
    }

    {msg, context}
  end

  @doc false
  # Generates LLM response using the built context
  defp generate_llm_response({msg, context}, :standard) do
    openai = LLM.get_client()
    response = openai |> LLM.generate_response!(context, :standard)
    {msg, response}
  end

  defp generate_llm_response({msg, context}, :jailbreak) do
    openai = LLM.get_client()
    response = openai |> LLM.generate_response!(context, :jailbreak)
    {msg, response}
  end

  @doc false
  # Sends the response to Discord via API
  defp send_discord_response({msg, response}, channel_id, message_id) do
    {:ok, _} =
      Api.Message.create(channel_id,
        content: response,
        message_reference: %{message_id: message_id}
      )

    {msg, response}
  end

  @doc false
  # Updates user metrics after successful interaction
  defp update_user_metrics({_msg, _response}, guild_id, user_id) do
    Accounts.update_user_metrics(guild_id, user_id)
  end

  @doc false
  # Sends a rate limit warning to the channel.
  defp send_rate_limit_warning(channel_id, :channel) do
    Api.Message.create(channel_id,
      content: "This channel is sending messages too quickly! Please wait a moment."
    )
  end

  defp send_rate_limit_warning(channel_id, :error) do
    Api.Message.create(channel_id,
      content: "Sorry, there was an error checking your message limit. Please try again later."
    )
  end

  @doc false
  # Sends a user-specific rate limit warning.
  defp send_user_rate_limit_warning(channel_id, user_id) do
    case RateLimiting.get_user_status(user_id) do
      {:ok, status} ->
        message = build_rate_limit_message(status)
        Api.Message.create(channel_id, content: message)

      {:error, _reason} ->
        Api.Message.create(channel_id,
          content:
            "You've run out of message credits! Vote for the bot to get more credits.\n" <>
              "#{TetoBot.Constants.vote_url()}"
        )
    end
  end

  defp build_rate_limit_message(%{message_credits: _credits, is_voted_user: true}) do
    "Thanks for voting! Your credits will refill to #{RateLimiting.get_daily_credit_refill_cap()} at midnight UTC, " <>
      "or vote again on top.gg for another #{RateLimiting.get_vote_credit_bonus()} credits immediately."
  end

  defp build_rate_limit_message(%{message_credits: credits}) do
    "You've run out of message credits! (#{credits} remaining) " <>
      "Vote for the bot on top.gg to get #{RateLimiting.get_vote_credit_bonus()} credits immediately, " <>
      "plus your credits will refill to #{RateLimiting.get_daily_credit_refill_cap()} every day at midnight UTC.\n" <>
      "#{TetoBot.Constants.vote_url()}"
  end
end
