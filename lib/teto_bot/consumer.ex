defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias TetoBot.Guilds
  alias Nostrum.Api
  alias Nostrum.Struct.Guild

  alias TetoBot.Channels
  alias TetoBot.Commands
  alias TetoBot.Interactions
  alias TetoBot.Messages

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Commands.register_commands(guilds)
  end

  def handle_event({:GUILD_CREATE, %Guild{id: new_guild_id} = _new_guild, _}) do
    case Guilds.member?(new_guild_id) do
      false ->
        Guilds.create(new_guild_id)
        Logger.info("New guild #{new_guild_id} joined!")

      _ ->
        :ok
    end
  end

  def handle_event({:GUILD_DELETE, {%Guild{id: old_guild_id}, _}, _}) do
    case Guilds.member?(old_guild_id) do
      true ->
        Guilds.delete(old_guild_id)
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
        Messages.handle_msg(msg)
      rescue
        e in RuntimeError ->
          Logger.error("Message processing error: #{inspect(e)}")

          cond do
            String.starts_with?(e.message, "Audio attachment are not supported: ") ->
              Api.Message.create(msg.channel_id,
                content: "Voice messages are not supported yet"
              )

            true ->
              Api.Message.create(msg.channel_id,
                content: "Oops, something went wrong! Try again, okay?"
              )
          end

          :ok
      end
    else
      Logger.debug("Ignoring message from non-whitelisted channel: #{msg.channel_id}")
      :ok
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
