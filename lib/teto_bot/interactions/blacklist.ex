defmodule TetoBot.Interactions.Blacklist do
  @moduledoc """
  Handles the /blacklist Discord slash command.
  """

  require Logger

  alias Nostrum.Struct.Interaction
  alias TetoBot.Channels
  alias TetoBot.Interactions.{Responses, Permissions}

  @spec handle_blacklist(Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /blacklist command - removes a channel from the whitelist.
  """
  def handle_blacklist(%Interaction{guild_id: guild_id, channel_id: channel_id} = interaction) do
    Permissions.with_permission(interaction, :manage_channels, fn ->
      case Channels.blacklist_channel(guild_id, channel_id) do
        {:ok, _channel} ->
          Responses.success(
            interaction,
            "Channel <##{channel_id}> has been removed from the whitelist.",
            ephemeral: true
          )

        {:error, :not_found} ->
          Responses.success(
            interaction,
            "Channel <##{channel_id}> was not found in the whitelist.",
            ephemeral: true
          )

        {:error, reason} ->
          Logger.error("Failed to blacklist channel <##{channel_id}>: #{inspect(reason)}")

          Responses.error(
            interaction,
            "An error occurred while trying to remove channel <##{channel_id}> from the whitelist."
          )
      end
    end)
  end
end
