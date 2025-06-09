defmodule TetoBot.Accounts.DailyResetWorker do
  @moduledoc """
  An Oban worker responsible for resetting daily message counts for all users
  at midnight UTC each day.

  This ensures consistent daily reset timing across all users and prevents
  race conditions that could occur with per-message daily checks.

  Scheduled via Oban cron to run at midnight UTC daily.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query

  alias TetoBot.Accounts.UserGuild

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("DailyResetWorker: Starting daily message count reset")

    case reset_all_daily_counts() do
      {:ok, reset_count} ->
        Logger.info("DailyResetWorker: Successfully reset #{reset_count} user daily counts")
        :ok

      {:error, reason} ->
        Logger.error("DailyResetWorker: Failed to reset daily counts. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Manually trigger a daily reset job.
  """
  def trigger do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp reset_all_daily_counts do
    # Reset daily_message_count to 0 for all users where it's > 0
    case UserGuild
         |> Ash.Query.for_read(:read)
         |> Ash.Query.filter(daily_message_count > 0)
         |> Ash.read() do
      {:ok, user_guilds} ->
        reset_count =
          Enum.reduce(user_guilds, 0, fn user_guild, count ->
            case user_guild
                 |> Ash.Changeset.for_update(:update, %{daily_message_count: 0})
                 |> Ash.update() do
              {:ok, _} ->
                count + 1

              {:error, reason} ->
                Logger.error(
                  "Failed to reset daily count for user #{user_guild.user_id} in guild #{user_guild.guild_id}: #{inspect(reason)}"
                )

                count
            end
          end)

        {:ok, reset_count}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
