defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct.Message.Attachment
  alias Nostrum.Api.Message
  alias Nostrum.Api
  alias Nostrum.Bot

  alias Nostrum.Struct.Message
  alias Nostrum.Struct.User
  alias Nostrum.Struct.Interaction

  alias TetoBot.Channels
  alias TetoBot.LLM
  alias TetoBot.RateLimiter
  alias TetoBot.MessageContext

  # CHANNEL_MESSAGE_WITH_SOURCE
  @interaction_response_type 4

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Logger.debug("#{inspect(guilds)}")

    commands = [
      %{
        name: "ping",
        description: "check alive"
      },
      %{
        name: "whitelist",
        description: "Whitelist a channel for the bot to operate in.",
        options: [
          %{
            # Channel type
            type: 7,
            name: "channel",
            description: "The channel to whitelist",
            required: true
          }
        ]
      },
      %{
        name: "blacklist",
        description: "Remove a channel from whitelist",
        options: [
          %{
            # Channel type
            type: 7,
            name: "channel",
            description: "The channel to blacklist",
            required: true
          }
        ]
      }
    ]

    # TODO: Proper queuing and dispatching
    guilds
    |> Enum.map(fn guild ->
      commands
      |> Enum.map(fn command ->
        Api.ApplicationCommand.create_guild_command(guild.id, command)
      end)
    end)
  end

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "ping"}} = interaction, _ws_state}
      ) do
    response = %{
      type: @interaction_response_type,
      data: %{
        content: "pong"
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "whitelist"}} = interaction, _ws_state}
      ) do
    channel_id = get_channel_id_from_options(interaction.data.options)

    case Channels.whitelist_channel(channel_id) do
      {:ok, _channel} ->
        response = %{
          # CHANNEL_MESSAGE_WITH_SOURCE
          type: @interaction_response_type,
          data: %{
            content: "Channel <##{channel_id}> whitelisted successfully!"
          }
        }

        Api.Interaction.create_response(interaction, response)

      {:error, changeset} ->
        Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(changeset.errors)}")
        {error_msg, _} = changeset.errors |> Keyword.get(:channel_id)

        response_content =
          if is_binary(error_msg) && error_msg |> String.contains?("has already been taken") do
            "Channel <##{channel_id}> is already whitelisted."
          else
            "Failed to whitelist channel <##{channel_id}>. Please check the logs."
          end

        response = %{
          # CHANNEL_MESSAGE_WITH_SOURCE
          type: @interaction_response_type,
          data: %{
            content: response_content
          }
        }

        Api.Interaction.create_response(interaction, response)
    end
  end

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "blacklist"}} = interaction, _ws_state}
      ) do
    channel_id = get_channel_id_from_options(interaction.data.options)

    case Channels.blacklist_channel(channel_id) do
      {:ok, _channel} ->
        response = %{
          type: @interaction_response_type,
          data: %{
            content: "Channel <##{channel_id}> has been removed from the whitelist."
          }
        }

        Api.Interaction.create_response(interaction, response)

      {:error, :not_found} ->
        response = %{
          type: @interaction_response_type,
          data: %{
            content: "Channel <##{channel_id}> was not found in the whitelist."
          }
        }

        Api.Interaction.create_response(interaction, response)

      # Catch other potential errors from Repo.delete
      {:error, reason} ->
        Logger.error("Failed to blacklist channel <##{channel_id}>: #{inspect(reason)}")

        response = %{
          type: @interaction_response_type,
          data: %{
            content:
              "An error occurred while trying to remove channel <##{channel_id}> from the whitelist."
          }
        }

        Api.Interaction.create_response(interaction, response)
    end
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
  def handle_event(_), do: :ok

  ## Helpers
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
           author: %User{username: username},
           content: content,
           attachments: attachments,
           channel_id: channel_id,
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
          # Override content field with image summary, then update the cache
          update_payload = %{
            id: msg.id,
            content: image_summary
          }

          MessageCache.Mnesia.update(update_payload)

        {:error, reason} ->
          Logger.error("Failed to summarize image: #{inspect(reason)}")
          Api.Message.create(channel_id, content: "Failed to process the image. Try again later.")
      end
    end

    context = MessageContext.get_context(channel_id)
    response = openai |> LLM.generate_response(context)

    {:ok, _} =
      Api.Message.create(channel_id,
        content: response,
        message_reference: %{message_id: message_id}
      )

    :ok
  end

  defp send_rate_limit_warning(channel_id) do
    Api.Message.create(channel_id,
      content: "You're sending messages too quickly! Please wait a moment."
    )
  end

  defp get_channel_id_from_options(options) do
    Enum.find(options, fn opt -> opt.name == "channel" end).value
  end
end
