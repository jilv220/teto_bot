defmodule TetoBot.Interactions.Whitelist do
  @moduledoc """
  Handles the /whitelist Discord slash command.
  """

  require Logger

  alias Nostrum.Struct.Interaction
  alias TetoBot.Channels
  alias TetoBot.Interactions.{Responses, Permissions}

  @spec handle_whitelist(Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /whitelist command - adds a channel to the whitelist for bot operation.
  """
  def handle_whitelist(%Interaction{guild_id: guild_id, channel_id: channel_id} = interaction) do
    Permissions.with_permission(interaction, :manage_channels, fn ->
      case Channels.whitelist_channel(guild_id, channel_id) do
        {:ok, _channel} ->
          Responses.success(
            interaction,
            "Channel <##{channel_id}> whitelisted successfully!",
            ephemeral: true
          )

        {:error, error} ->
          Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(error)}")
          error_message = build_error_message(error, channel_id)
          Responses.error(interaction, error_message)
      end
    end)
  end

  @spec build_error_message(any(), integer()) :: String.t()
  defp build_error_message(error, channel_id) do
    case error do
      %Ash.Error.Invalid{errors: errors} ->
        if Enum.any?(errors, &String.contains?(inspect(&1), "unique")) do
          "Channel <##{channel_id}> is already whitelisted."
        else
          "Failed to whitelist channel <##{channel_id}>. Please check the logs."
        end

      _ ->
        "Failed to whitelist channel <##{channel_id}>. Please check the logs."
    end
  end
end
