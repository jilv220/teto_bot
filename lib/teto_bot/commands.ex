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
  Registers slash commands based on the runtime environment.

  In :dev, registers guild commands for the configured development guild.
  In :prod, registers global commands.

  ## Parameters
  - guilds: A list of Nostrum.Struct.Guild structs from the READY event.

  ## Returns
  - `:ok` on success, logs errors if any command registration fails.
  """
  def register_commands(guilds) do
    case Application.get_env(:teto_bot, :env, :dev) do
      :dev ->
        register_guild_commands(guilds)

      :prod ->
        register_global_commands()
    end
  end

  @doc """
  Unregisters all global slash commands for the bot.

  ## Returns
  - `:ok` on success, logs errors if any command unregistration fails.
  """
  def unregister_commands do
    case Api.ApplicationCommand.global_commands() do
      {:ok, commands} ->
        Enum.each(commands, fn command ->
          case Api.ApplicationCommand.delete_global_command(command.id) do
            :ok ->
              Logger.debug("Unregistered global command #{command.name}")

            {:error, reason} ->
              Logger.error(
                "Failed to unregister global command #{command.name}: #{inspect(reason)}"
              )
          end
        end)

      {:error, reason} ->
        Logger.error("Failed to fetch global commands: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Unregisters all slash commands for a specific guild.

  ## Parameters
  - guild_id: The ID of the guild to unregister commands from.

  ## Returns
  - `:ok` on success, logs errors if any command unregistration fails.
  """
  def unregister_guild_commands(guild_id) do
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

  defp register_guild_commands(guilds) do
    dev_guild_id = Application.get_env(:teto_bot, :dev_guild_id)

    case Enum.find(guilds, &(&1.id == dev_guild_id)) do
      %{id: guild_id} ->
        Enum.each(commands(), fn command ->
          case Api.ApplicationCommand.create_guild_command(guild_id, command) do
            {:ok, _} ->
              Logger.debug("Registered command #{command.name} for dev guild #{guild_id}")

            {:error, reason} ->
              Logger.error(
                "Failed to register command #{command.name} for dev guild #{guild_id}: #{inspect(reason)}"
              )
          end
        end)

      nil ->
        Logger.warning(
          "Development guild #{dev_guild_id} not found in READY event guilds, skipping command registration"
        )
    end

    :ok
  end

  defp register_global_commands do
    Enum.each(commands(), fn command ->
      case Api.ApplicationCommand.create_global_command(command) do
        {:ok, _} ->
          Logger.debug("Registered global command #{command.name}")

        {:error, reason} ->
          Logger.error("Failed to register global command #{command.name}: #{inspect(reason)}")
      end
    end)

    :ok
  end
end
