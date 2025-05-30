defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias TetoBot.Leaderboards
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Api.Message
  alias Nostrum.Api
  alias Nostrum.Bot

  alias Nostrum.Struct.Guild
  alias Nostrum.Struct.Message
  alias Nostrum.Struct.Message.Attachment
  alias Nostrum.Struct.User

  alias TetoBot.Channels
  alias TetoBot.Commands
  alias TetoBot.Interactions
  alias TetoBot.LLM
  alias TetoBot.RateLimiter

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Commands.register_commands(guilds)
  end

  def handle_event({:GUILD_CREATE, %Guild{id: new_guild_id} = _new_guild, _}) do
    case TetoBot.Cache.Guild.exists?(new_guild_id) do
      {:ok, false} ->
        TetoBot.Cache.Guild.add_id(new_guild_id)
        Logger.info("New guild #{new_guild_id} joined!")

      _ ->
        :ok
    end
  end

  def handle_event({:GUILD_DELETE, {%Guild{id: old_guild_id}, _}, _}) do
    case TetoBot.Cache.Guild.exists?(old_guild_id) do
      {:ok, true} ->
        TetoBot.Cache.Guild.remove_id(old_guild_id)
        Logger.info("Guild #{old_guild_id} has left us!")

      _ ->
        :ok
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction, ws_state}) do
    Interactions.handle_interaction(interaction, ws_state)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if Channels.whitelisted?(msg.channel_id) do
      try do
        handle_msg(msg)
      rescue
        e in RuntimeError ->
          Logger.error("Text generation error: #{inspect(e)}")

          Api.Message.create(msg.channel_id,
            content: "Oops, something went wrong! Try again, okay?"
          )

          :ok
      end
    else
      Logger.debug("Ignoring message from non-whitelisted channel: #{msg.channel_id}")
      :ok
    end
  end

  # Ignore any other events
  def handle_event({evt_name, _, _}) do
    IO.inspect(evt_name)
    :ok
  end

  defp handle_msg(
         %Message{
           message_reference: msg_ref,
           author: %User{id: author_id}
         } = msg
       ) do
    bot_id = Bot.get_bot_name()

    # Skip if the message is from the bot itself
    if author_id == bot_id do
      :ok
    else
      # Check if the message is a reply to the bot
      case msg_ref do
        %{message_id: replied_msg_id} ->
          case MessageCache.get(replied_msg_id) do
            {:ok, replied_to_msg} ->
              # Only proceed if the replied-to message is from the bot
              if replied_to_msg.author.id == bot_id do
                process_message(msg)
              else
                Logger.debug("Ignoring reply to non-bot message: #{replied_msg_id}")
                :ok
              end

            {:error, reason} ->
              Logger.error(
                "Failed to fetch replied message #{replied_msg_id}: #{inspect(reason)}"
              )

              :ok
          end

        nil ->
          # Process non-reply messages
          process_message(msg)
      end
    end
  end

  defp process_message(%Message{author: %User{id: user_id}, channel_id: channel_id} = msg) do
    if RateLimiter.allow?(user_id) do
      generate_and_send_response(msg)
    else
      send_rate_limit_warning(channel_id)
    end
  end

  defp generate_and_send_response(
         %Message{
           author: %User{username: username, id: user_id},
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
      [%Attachment{url: url} | _] = attachments
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
