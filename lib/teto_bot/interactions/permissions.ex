defmodule TetoBot.Interactions.Permissions do
  @moduledoc """
  Handles permission checking for Discord interactions.
  """

  require Logger

  alias Nostrum.Api.Guild
  alias Nostrum.Struct.Interaction
  alias TetoBot.Channels
  alias TetoBot.Interactions.Responses

  @spec can_manage_channels?(Interaction.t()) :: boolean()
  @doc """
  Checks if the user invoking the interaction has the "Manage Channels" permission.
  """
  def can_manage_channels?(%Interaction{guild_id: guild_id, member: member})
      when not is_nil(guild_id) and not is_nil(member) do
    case Guild.get(guild_id) do
      {:ok, guild} ->
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

  @spec with_permission(Interaction.t(), atom(), function()) :: any()
  @doc """
  Executes a function if the user has the specified permission.

  ## Parameters
  - interaction: The Discord interaction
  - permission: The permission to check (:manage_channels)
  - fun: Function to execute if permission is granted
  """
  def with_permission(interaction, :manage_channels, fun) do
    if can_manage_channels?(interaction) do
      fun.()
    else
      Responses.permission_denied(interaction)
    end
  end

  @spec with_whitelisted_channel(Interaction.t(), integer(), function()) :: any()
  @doc """
  Executes a function if the channel is whitelisted.

  ## Parameters
  - interaction: The Discord interaction
  - channel_id: The channel ID to check
  - fun: Function to execute if channel is whitelisted
  """
  def with_whitelisted_channel(interaction, channel_id, fun) do
    case Channels.whitelisted?(channel_id) do
      {:ok, true} ->
        fun.()

      {:ok, false} ->
        Responses.whitelist_only(interaction)
    end
  end
end
