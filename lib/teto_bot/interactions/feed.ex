defmodule TetoBot.Interactions.Feed do
  @moduledoc """
  Handles the /feed Discord slash command.
  """

  require Logger

  alias Nostrum.Struct.Interaction
  alias TetoBot.{Accounts, Format}
  alias TetoBot.Interactions.{Permissions, Responses}

  @spec handle_feed(Interaction.t(), integer(), integer(), integer()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /feed command - allows users to feed Teto to increase intimacy.
  """
  def handle_feed(interaction, user_id, guild_id, channel_id) do
    Permissions.with_whitelisted_channel(interaction, channel_id, fn ->
      case Accounts.check_feed_cooldown(guild_id, user_id) do
        {:ok, :allowed} ->
          execute_feed_command(interaction, user_id, guild_id)

        {:error, time_left} ->
          interaction
          |> Responses.success(build_cooldown_message(time_left))
      end
    end)
  end

  @spec execute_feed_command(Interaction.t(), integer(), integer()) :: :ok | Nostrum.Api.error()
  defp execute_feed_command(interaction, user_id, guild_id) do
    case Accounts.feed_teto(guild_id, user_id, 5) do
      {:ok, _changes} ->
        case Accounts.get_intimacy(guild_id, user_id) do
          {:ok, intimacy} ->
            success_message = build_feed_success_message(intimacy)
            Responses.success(interaction, success_message)

          {:error, reason} ->
            Logger.error(
              "Failed to get intimacy after feeding for user #{user_id}: #{inspect(reason)}"
            )

            Responses.success(
              interaction,
              build_feed_success_message()
            )
        end

      {:error, reason} ->
        Logger.error(
          "Failed to feed Teto for user #{user_id} in guild #{guild_id} with reason: #{inspect(reason)}"
        )

        Responses.error(interaction, "Something went wrong while feeding Teto. Please try again.")
    end
  end

  def build_cooldown_message(time_left \\ nil) do
    if time_left do
      "You've already fed Teto today! Try again in #{Format.format_time_left(time_left)}."
    else
      "You've already fed Teto today!"
    end
  end

  def build_feed_success_message(intimacy \\ nil) do
    if intimacy do
      "You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: #{intimacy}. 💖"
    else
      "You fed Teto! Your intimacy with her increased by 5."
    end
  end
end
