defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  require Logger

  alias Nostrum.Api
  alias Nostrum.Struct.Guild

  alias TetoBot.Channels
  alias TetoBot.Commands
  alias TetoBot.Guilds
  alias TetoBot.Interactions
  alias TetoBot.Messages

  def handle_event({:READY, %{guilds: guilds} = _msg, _}) do
    Commands.register_commands(guilds)
  end

  def handle_event({:GUILD_CREATE, %Guild{id: new_guild_id} = _new_guild, _}) do
    case Guilds.member_check(new_guild_id) do
      {:ok, false} ->
        case Guilds.create_guild(new_guild_id) do
          {:ok, _guild} ->
            Logger.info("New guild #{new_guild_id} joined!")

          {:error, reason} ->
            Logger.error("Failed to create guild #{new_guild_id}: #{inspect(reason)}")
        end

      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to check guild membership for #{new_guild_id}: #{inspect(reason)}")
    end
  end

  def handle_event({:GUILD_DELETE, {%Guild{id: old_guild_id}, _}, _}) do
    case Guilds.member_check(old_guild_id) do
      {:ok, true} ->
        case Guilds.delete_guild(old_guild_id) do
          {:ok, _guild} ->
            Logger.info("Guild #{old_guild_id} has left us!")

          {:error, reason} ->
            Logger.error("Failed to delete guild #{old_guild_id}: #{inspect(reason)}")
        end

      {:ok, false} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to check guild membership for #{old_guild_id}: #{inspect(reason)}")
    end
  end

  def handle_event({:INTERACTION_CREATE, interaction, ws_state}) do
    Interactions.handle_interaction(interaction, ws_state)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    case Channels.whitelisted?(msg.channel_id) do
      {:ok, true} ->
        try do
          Messages.handle_msg(msg)
          :ok
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

      {:ok, false} ->
        Logger.debug("Ignoring message from non-whitelisted channel: #{msg.channel_id}")
        :ok
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
