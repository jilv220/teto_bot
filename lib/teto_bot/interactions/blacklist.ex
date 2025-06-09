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

        {:error, error} ->
          Logger.error("Failed to blacklist channel <##{channel_id}>: #{inspect(error)}")
          error_msg = build_error_message(error, channel_id)

          Responses.error(
            interaction,
            error_msg
          )
      end
    end)
  end

  @spec build_error_message(any(), integer()) :: String.t()
  defp build_error_message(error, channel_id) do
    case error do
      %Ash.Error.Invalid{errors: errors} ->
        if Enum.any?(errors, &String.contains?(inspect(&1), "NotFound")) do
          "Channel <##{channel_id}> was not found in the whitelist."
        else
          "Failed to blacklist channel <##{channel_id}>. Please check the logs."
        end

      _ ->
        "Failed to blacklist channel <##{channel_id}>. Please check the logs."
    end
  end
end
