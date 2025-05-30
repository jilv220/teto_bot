defmodule TetoBot.Messages do
  require Logger

  alias Nostrum.Api
  alias Nostrum.Bot
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct

  alias TetoBot.Leaderboards
  alias TetoBot.LLM
  alias TetoBot.RateLimiter

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
      generate_and_send_response(msg)
    else
      send_rate_limit_warning(channel_id)
    end
  end

  defp generate_and_send_response(
         %Struct.Message{
           author: %Struct.User{username: username, id: user_id},
           content: content,
           attachments: attachments,
           channel_id: channel_id,
           guild_id: guild_id,
           id: message_id
         } = msg
       ) do
    Logger.info("New msg from #{username}: #{inspect(content)}")

    openai = LLM.get_client()

    # Handle image attachments
    attachments = attachments || []

    if length(attachments) > 0 do
      # Only process first attachment to save tokens
      [%Struct.Message.Attachment{url: url} | _] = attachments
      Logger.info("Image url: #{url}")

      case LLM.summarize_image(openai, url) do
        {:ok, image_summary} ->
          Logger.debug("Image summary: #{inspect(image_summary)}")
          # Attach content field with image summary, then update the cache
          update_payload = %{
            id: msg.id,
            content: content <> " Image attachment: " <> image_summary
          }

          MessageCache.Mnesia.update(update_payload)

        {:error, reason} ->
          Logger.error("Failed to summarize image: #{inspect(reason)}")
          Api.Message.create(channel_id, content: "Failed to process the image. Try again later.")
      end
    end

    # Build context map
    context = %{
      messages: TetoBot.MessageContext.get_context(channel_id),
      guild_id: guild_id,
      user_id: user_id
    }

    response = openai |> LLM.generate_response!(context)

    {:ok, _} =
      Api.Message.create(channel_id,
        content: response,
        message_reference: %{message_id: message_id}
      )

    Leaderboards.increment_intimacy!(guild_id, user_id, 1)

    :ok
  end

  defp send_rate_limit_warning(channel_id) do
    Api.Message.create(channel_id,
      content: "You're sending messages too quickly! Please wait a moment."
    )
  end
end
