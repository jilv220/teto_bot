defmodule TetoBot.Interactions do
  @moduledoc """
  Handles Discord interaction-related functionality, such as processing commands and creating responses.
  """

  require Logger

  alias Nostrum.Api
  alias Nostrum.Api.Guild
  alias Nostrum.Struct.Interaction
  alias TetoBot.Channels
  alias TetoBot.Constants
  alias TetoBot.Commands

  @doc """
  Handles an interaction event by dispatching to the appropriate command handler.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.
  - ws_state: The WebSocket state (passed through for compatibility, unused).

  ## Returns
  - The result of the interaction handler or :ok if unhandled.
  """
  def handle_interaction(%Interaction{data: %{name: "ping"}} = interaction, _ws_state) do
    create_ephemeral_response(interaction, "pong")
  end

  def handle_interaction(%Interaction{data: %{name: "help"}} = interaction, _ws_state) do
    help_message = """
    **TetoBot Help**

    TetoBot is a Discord bot that cosplays as Kasane Teto and responds to messages in whitelisted channels, powered by AI to generate contextual replies. Below is a list of available commands:

    **Commands:**
    #{Enum.map_join(Commands.commands(), "\n", fn cmd -> "- **/#{cmd.name}**: #{cmd.description}#{if Map.has_key?(cmd, :options), do: "\n  - Options: #{format_options(cmd.options)}", else: ""}" end)}

    **Usage:**
    - Use `/ping` to check if the bot is online.
    - Use `/whitelist` or `/blacklist` to manage channels where the bot can respond (requires Manage Channels permission).
    - Send messages in whitelisted channels to interact with the bot's AI responses.

    **Support:**
    For issues or feedback, please create an issue in our [Github Repo](https://github.com/jilv220/teto_bot/issues)
    """

    create_ephemeral_response(interaction, help_message)
  end

  def handle_interaction(%Interaction{data: %{name: "whitelist"}} = interaction, _ws_state) do
    if can_manage_channels?(interaction) do
      channel_id = get_channel_id_from_options(interaction.data.options)

      case Channels.whitelist_channel(channel_id) do
        {:ok, _channel} ->
          create_ephemeral_response(
            interaction,
            "Channel <##{channel_id}> whitelisted successfully!"
          )

        {:error, changeset} ->
          Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(changeset.errors)}")
          {error_msg, _} = changeset.errors |> Keyword.get(:channel_id)

          response_content =
            if is_binary(error_msg) && error_msg |> String.contains?("has already been taken") do
              "Channel <##{channel_id}> is already whitelisted."
            else
              "Failed to whitelist channel <##{channel_id}>. Please check the logs."
            end

          create_ephemeral_response(interaction, response_content)
      end
    else
      create_ephemeral_response(
        interaction,
        "You do not have permission to use this command. Only users with Manage Channels permission can use this command."
      )
    end
  end

  def handle_interaction(%Interaction{data: %{name: "blacklist"}} = interaction, _ws_state) do
    if can_manage_channels?(interaction) do
      channel_id = get_channel_id_from_options(interaction.data.options)

      case Channels.blacklist_channel(channel_id) do
        {:ok, _channel} ->
          create_ephemeral_response(
            interaction,
            "Channel <##{channel_id}> has been removed from the whitelist."
          )

        {:error, :not_found} ->
          create_ephemeral_response(
            interaction,
            "Channel <##{channel_id}> was not found in the whitelist."
          )

        {:error, reason} ->
          Logger.error("Failed to blacklist channel <##{channel_id}>: #{inspect(reason)}")

          create_ephemeral_response(
            interaction,
            "An error occurred while trying to remove channel <##{channel_id}> from the whitelist."
          )
      end
    else
      create_ephemeral_response(
        interaction,
        "You do not have permission to use this command. Only users with Manage Channels permission can use this command."
      )
    end
  end

  def handle_interaction(_interaction, _ws_state), do: :ok

  @doc """
  Creates an ephemeral response for a Discord interaction.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.
  - content: The string content of the ephemeral response.

  ## Returns
  - The result of Nostrum.Api.Interaction.create_response/2.
  """
  def create_ephemeral_response(interaction, content) do
    response = %{
      type: Constants.interaction_response_type(),
      data: %{
        content: content,
        flags: Constants.ephemeral_flag()
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  @doc """
  Checks if the user invoking the interaction has the "Manage Channels" permission.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.

  ## Returns
  - `true` if the user has "Manage Channels" permission, `false` otherwise.
  """
  def can_manage_channels?(%Interaction{guild_id: guild_id, member: member})
      when not is_nil(guild_id) and not is_nil(member) do
    case Guild.get(guild_id) do
      {:ok, guild} ->
        # Ignore channel permission override, otherwise I ll go bankrupt
        :manage_channels in Nostrum.Struct.Guild.Member.guild_permissions(member, guild)

      {:error, reason} ->
        Logger.error("Failed to get guild: #{inspect(reason)}")
        false
    end
  end

  def can_manage_channels?(_interaction) do
    Logger.debug("Interaction lacks guild or member data, denying permission")
    false
  end

  defp get_channel_id_from_options(options) do
    Enum.find(options, fn opt -> opt.name == "channel" end).value
  end

  defp format_options(options) do
    Enum.map_join(options, ", ", fn opt ->
      "#{opt.name} (#{opt.description}, #{if opt.required, do: "required", else: "optional"})"
    end)
  end
end
