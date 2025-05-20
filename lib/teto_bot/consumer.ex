defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias Nostrum.Api
  alias Nostrum.Bot
  alias Nostrum.Struct.User
  alias Nostrum.Struct.Interaction

  alias TetoBot.LLM

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Logger.debug("#{inspect(guilds)}")

    # TODO: Use proper storage, queue and dispatch...
    commands = [
      %{
        name: "ping",
        description: "check alive"
      },
      %{
        name: "channelrestrict",
        description: "Restrict to this channel"
      }
    ]

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
      type: 4,
      data: %{
        content: "pong"
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "channelrestrict"}} = interaction,
         _ws_state}
      ) do
    response = %{
      type: 4,
      data: %{
        content: "pong"
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    try do
      %User{id: id, username: username} = msg.author

      # Why is this bot_name instead of bot_id o algo
      if id != Bot.get_bot_name() do
        Logger.info("New msg from #{username}: #{inspect(msg.content)}")
        openai = LLM.get_client()
        response = openai |> LLM.generate_response(msg.content)

        Api.Message.create(msg.channel_id,
          content: response,
          message_reference: %{
            message_id: msg.id
          }
        )
      else
        # Ignore itself
        :ok
      end
    rescue
      e in RuntimeError ->
        Logger.error("Text generation error: #{inspect(e)}")

        Api.Message.create(msg.channel_id,
          content: "Oops, something went wrong! Try again, okay?"
        )

        :ok
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
