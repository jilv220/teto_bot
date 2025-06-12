defmodule TetoBot.Accounts.DailyResetWorker do
  @moduledoc """
  Background job that recharges user message credits and resets daily metrics
  at midnight UTC each day.

  This worker is responsible for:
  - Adding 10 message credits to all users (charging system)
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
    Logger.info("DailyResetWorker: Starting daily credit recharge and metric reset")

    with {:ok, credit_count} <- recharge_all_credits(),
         {:ok, reset_count} <- reset_all_daily_metrics() do
      Logger.info(
        "DailyResetWorker: Successfully recharged #{credit_count} users and reset #{reset_count} daily metrics"
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
    Logger.info("DailyResetWorker: Recharging message credits for all users")

    case User
         |> Ash.Query.for_read(:read)
         |> Ash.read() do
      {:ok, users} ->
        credit_count =
          Enum.reduce(users, 0, fn user, count ->
            new_credits = user.message_credits + RateLimiting.get_daily_credit_recharge()

            case user
                 |> Ash.Changeset.for_update(:update, %{message_credits: new_credits})
                 |> Ash.update() do
              {:ok, _} ->
                count + 1

              {:error, reason} ->
                Logger.error(
                  "Failed to recharge credits for user #{user.user_id}: #{inspect(reason)}"
                )

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
