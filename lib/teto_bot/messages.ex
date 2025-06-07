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

  alias TetoBot.Intimacy
  alias TetoBot.LLM
  alias TetoBot.Messages
  alias TetoBot.RateLimiter

  @spec handle_msg(Nostrum.Struct.Message.t()) :: :ok
  @doc """
  Handles an incoming Discord message, determining if it should be processed and executing the appropriate action.
  """
  def handle_msg(%Struct.Message{author: %Struct.User{id: author_id}} = msg) do
    bot_id = Bot.get_bot_name()

    msg
    |> should_process_message?(author_id, bot_id)
    |> maybe_process_message(msg, bot_id)
  end

  defp should_process_message?(_msg, author_id, bot_id) when author_id == bot_id,
    do: {:skip, :bot_message}

  defp should_process_message?(%Struct.Message{message_reference: nil}, _author_id, _bot_id),
    do: {:process, :direct}

  defp should_process_message?(
         %Struct.Message{message_reference: %{message_id: replied_msg_id}},
         _author_id,
         bot_id
       ) do
    case MessageCache.get(replied_msg_id) do
      {:ok, replied_to_msg} -> check_reply_target(replied_to_msg, bot_id, replied_msg_id)
      {:error, reason} -> {:error, reason, replied_msg_id}
    end
  end

  defp check_reply_target(replied_to_msg, bot_id, replied_msg_id) do
    if replied_to_msg.author.id == bot_id do
      {:process, :reply_to_bot}
    else
      {:skip, {:reply_to_user, replied_msg_id}}
    end
  end

  defp maybe_process_message({:process, _reason}, msg, _bot_id), do: process_message(msg)
  defp maybe_process_message({:skip, :bot_message}, _msg, _bot_id), do: :ok

  defp maybe_process_message({:skip, {:reply_to_user, replied_msg_id}}, _msg, _bot_id) do
    Logger.debug("Ignoring reply to non-bot message: #{replied_msg_id}")
    :ok
  end

  defp maybe_process_message({:error, reason, replied_msg_id}, _msg, _bot_id) do
    Logger.error("Failed to fetch replied message #{replied_msg_id}: #{inspect(reason)}")
    :ok
  end

  defp process_message(
         %Struct.Message{author: %Struct.User{id: user_id}, channel_id: channel_id} = msg
       ) do
    if RateLimiter.allow?(user_id) do
      generate_and_send_response!(msg)
    else
      send_rate_limit_warning(channel_id)
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

    Logger.info("New msg from #{username}: #{inspect(msg.content)}")

    msg
    |> Messages.Attachment.process_attachments()
    |> build_message_context(guild_id, user_id, channel_id)
    |> generate_llm_response()
    |> send_discord_response(channel_id, message_id)
    |> update_user_intimacy!(guild_id, user_id)
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
  defp generate_llm_response({msg, context}) do
    openai = LLM.get_client()
    response = openai |> LLM.generate_response!(context)
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
  # Updates user intimacy after successful interaction
  defp update_user_intimacy!({_msg, _response}, guild_id, user_id) do
    case Intimacy.increment(guild_id, user_id, 1) do
      :ok ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "Failed to update user intimacy: #{inspect(reason)}"
    end
  end

  @spec send_rate_limit_warning(integer()) :: :ok
  @doc false
  # Sends a rate limit warning to the channel.
  defp send_rate_limit_warning(channel_id) do
    Api.Message.create(channel_id,
      content: "You're sending messages too quickly! Please wait a moment."
    )

    :ok
  end
end
