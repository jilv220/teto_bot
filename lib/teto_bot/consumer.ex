defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias Nostrum.Api.Message
  alias Nostrum.Api
  alias Nostrum.Bot

  alias Nostrum.Struct.Message
  alias Nostrum.Struct.User
  alias Nostrum.Struct.Interaction

  alias TetoBot.LLM
  alias TetoBot.RateLimiter
  alias TetoBot.MessageContext

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Logger.debug("#{inspect(guilds)}")

    commands = [
      %{
        name: "ping",
        description: "check alive"
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

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
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
         channel_id: channel_id,
         id: message_id
       }) do
    Logger.info("New msg from #{username}: #{inspect(content)}")

    MessageContext.store_message(user_id, content)
    context = MessageContext.get_context(user_id)

    openai = LLM.get_client()
    response = openai |> LLM.generate_response(context)

    Api.Message.create(channel_id,
      content: response,
      message_reference: %{message_id: message_id}
    )
  end

  defp send_rate_limit_warning(channel_id) do
    Api.Message.create(channel_id,
      content: "You're sending messages too quickly! Please wait a moment."
    )
  end
end
