defmodule TetoBot.Commands do
  @moduledoc """
  Manages registration and unregistration of Discord slash commands for TetoBot.
  """

  require Logger
  alias Nostrum.Api

  @doc """
  Returns the list of slash commands to register.
  """
  def commands do
    [
      %{
        name: "ping",
        description: "Check if the bot is alive"
      },
      %{
        name: "help",
        description: "Display information about the bot and its commands"
      },
      %{
        name: "whitelist",
        description:
          "Whitelist a channel for the bot to operate in (requires Manage Channels permission)",
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
        description: "Remove a channel from the whitelist (requires Manage Channels permission)",
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
  end

  @doc """
  Registers slash commands for all guilds the bot is in.

  ## Parameters
  - guilds: A list of Nostrum.Struct.Guild structs from the READY event.

  ## Returns
  - `:ok` on success, logs errors if any command registration fails.
  """
  def register_commands(guilds) do
    Enum.each(guilds, fn guild ->
      Enum.each(commands(), fn command ->
        case Api.ApplicationCommand.create_guild_command(guild.id, command) do
          {:ok, _} ->
            Logger.debug("Registered command #{command.name} for guild #{guild.id}")

          {:error, reason} ->
            Logger.error(
              "Failed to register command #{command.name} for guild #{guild.id}: #{inspect(reason)}"
            )
        end
      end)
    end)

    :ok
  end

  @doc """
  Unregisters all slash commands for a specific guild.

  ## Parameters
  - guild_id: The ID of the guild to unregister commands from.

  ## Returns
  - `:ok` on success, logs errors if any command unregistration fails.
  """
  def unregister_commands(guild_id) do
    case Api.ApplicationCommand.guild_commands(guild_id) do
      {:ok, commands} ->
        Enum.each(commands, fn command ->
          case Api.ApplicationCommand.delete_guild_command(guild_id, command.id) do
            :ok ->
              Logger.debug("Unregistered command #{command.name} for guild #{guild_id}")

            {:error, reason} ->
              Logger.error(
                "Failed to unregister command #{command.name} for guild #{guild_id}: #{inspect(reason)}"
              )
          end
        end)

      {:error, reason} ->
        Logger.error("Failed to fetch commands for guild #{guild_id}: #{inspect(reason)}")
    end

    :ok
  end
end
