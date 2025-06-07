defmodule TetoBot.Interactions.Feed do
  @moduledoc """
  Handles the /feed Discord slash command.
  """

  require Logger

  alias Nostrum.Struct.Interaction
  alias TetoBot.{Format, Intimacy, Users}
  alias TetoBot.Interactions.{Responses, Permissions}

  @spec handle_feed(Interaction.t(), integer(), integer(), integer()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /feed command - allows users to feed Teto to increase intimacy.
  """
  def handle_feed(interaction, user_id, guild_id, channel_id) do
    Permissions.with_whitelisted_channel(interaction, channel_id, fn ->
      case Users.check_feed_cooldown(guild_id, user_id) do
        {:ok, :allowed} ->
          execute_feed_command(interaction, user_id, guild_id)

        {:error, time_left} ->
          feed_cooldown_message =
            "You've already fed Teto today! Try again in #{Format.format_time_left(time_left)}."

          Responses.success(interaction, feed_cooldown_message)
      end
    end)
  end

  @spec execute_feed_command(Interaction.t(), integer(), integer()) :: :ok | Nostrum.Api.error()
  defp execute_feed_command(interaction, user_id, guild_id) do
    Users.set_feed_cooldown(guild_id, user_id)
    Intimacy.increment(guild_id, user_id, 5)

    case Intimacy.get(guild_id, user_id) do
      {:ok, intimacy} ->
        success_message =
          "You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: #{intimacy}. 💖"

        Responses.success(interaction, success_message)

      {:error, reason} ->
        Logger.error(
          "Failed to get intimacy after feeding for user #{user_id}: #{inspect(reason)}"
        )

        Responses.success(interaction, "You fed Teto! Your intimacy with her increased by 5. 💖")
    end
  end
end
