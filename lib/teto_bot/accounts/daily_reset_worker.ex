defmodule TetoBot.Accounts.DailyResetWorker do
  @moduledoc """
  Background job that refills user message credits and resets daily metrics
  at midnight UTC each day.

  This worker is responsible for:
  - Refilling message credits to daily cap for users below the threshold (refill system)
  - Resetting daily_message_count to 0 for all user_guilds (usage tracking)
  - Clearing feed_cooldown_until timestamps for all user_guilds

  Scheduled via Oban cron to run at midnight UTC daily.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query

  alias TetoBot.Accounts.{User, UserGuild}
  alias TetoBot.RateLimiting

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("DailyResetWorker: Starting daily credit refill and metric reset")

    with {:ok, credit_count} <- recharge_all_credits(),
         {:ok, reset_count} <- reset_all_daily_metrics() do
      Logger.info(
        "DailyResetWorker: Successfully refilled #{credit_count} users and reset #{reset_count} daily metrics"
      )

      :ok
    else
      {:error, reason} ->
        Logger.error(
          "DailyResetWorker: Failed to complete daily reset. Reason: #{inspect(reason)}"
        )

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

  defp recharge_all_credits do
    Logger.info("DailyResetWorker: Refilling message credits for users below the daily cap")

    refill_cap = RateLimiting.get_daily_credit_refill_cap()

    case User
         |> Ash.Query.for_read(:read)
         |> Ash.read() do
      {:ok, users} ->
        credit_count =
          Enum.reduce(users, 0, fn user, count ->
            current_credits = user.message_credits || 0

            if current_credits < refill_cap do
              case user
                   |> Ash.Changeset.for_update(:update, %{message_credits: refill_cap})
                   |> Ash.update() do
                {:ok, _} ->
                  count + 1

                {:error, reason} ->
                  Logger.error(
                    "Failed to refill credits for user #{user.user_id}: #{inspect(reason)}"
                  )

                  count
              end
            else
              # User already has credits >= refill_cap, no change needed
              count
            end
          end)

        {:ok, credit_count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp reset_all_daily_metrics do
    Logger.info("DailyResetWorker: Resetting daily message counts and feed cooldowns")

    # Reset daily_message_count to 0 and last_feed to nil for all users where needed
    case UserGuild
         |> Ash.Query.for_read(:read)
         |> Ash.Query.filter(daily_message_count > 0 or not is_nil(last_feed))
         |> Ash.read() do
      {:ok, user_guilds} ->
        reset_count =
          Enum.reduce(user_guilds, 0, fn user_guild, count ->
            case user_guild
                 |> Ash.Changeset.for_update(:update, %{
                   daily_message_count: 0,
                   last_feed: nil
                 })
                 |> Ash.update() do
              {:ok, _} ->
                count + 1

              {:error, reason} ->
                Logger.error(
                  "Failed to reset daily metrics for user #{user_guild.user_id} in guild #{user_guild.guild_id}: #{inspect(reason)}"
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
