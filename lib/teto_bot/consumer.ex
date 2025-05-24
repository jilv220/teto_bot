defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

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
      Logger.info("Ignoring message from non-whitelisted channel: #{msg.channel_id}")
      :ok
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok

  ## Helpers
  defp handle_msg(msg) do
    if msg.author.id != Bot.get_bot_name() do
      if RateLimiter.allow?(msg.author.id) do
        generate_and_send_response(msg)
      else
        send_rate_limit_warning(msg.channel_id)
      end
    end
  end

  defp generate_and_send_response(%Message{
         author: %User{id: user_id, username: username},
         content: content,
         attachments: attachments,
         channel_id: channel_id,
         id: message_id
       }) do
    Logger.info("New msg from #{username}: #{inspect(content)}")

    openai = LLM.get_client()

    if length(attachments) > 0 do
      # Only pass first attachment to save tokens...
      [%Attachment{url: url} | _] = attachments
      Logger.info("Image url: #{url}")
      # Make sure attachment is actually image and convert to png/jpg, or ignore

      # Handle error
      {:ok, image_summary} = openai |> LLM.summarize_image(url)
      Logger.debug("#{inspect(image_summary)}")
      MessageContext.store_message(user_id, image_summary, :user)
    end

    MessageContext.store_message(user_id, content, :user)
    context = MessageContext.get_context(user_id)
    response = openai |> LLM.generate_response(context)

    {:ok, _} =
      Api.Message.create(channel_id,
        content: response,
        message_reference: %{message_id: message_id}
      )

    # Store the bot's response as assistant
    MessageContext.store_message(user_id, response, :assistant)

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
