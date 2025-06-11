defmodule TetoBot.UserRateLimiter do
  @moduledoc """
  User-specific rate limiter for controlling daily message limits based on voting status.

  Free users are limited to 10 messages per day.
  Users who have voted for the bot get 30 messages per day.
  Daily limits reset at midnight UTC.

  - `allow?/1` - Check if a user can send a message
  - `record_vote/1` - Record when a user votes for the bot
  - `get_user_status/1` - Get user's current rate limit status

  ## Usage

      TetoBot.UserRateLimiter.allow?(user_id)
      #=> {:ok, true} | {:ok, false} | {:error, reason}

      TetoBot.UserRateLimiter.record_vote(user_id)
      #=> :ok | {:error, reason}

      TetoBot.UserRateLimiter.get_user_status(user_id)
      #=> {:ok, %{daily_limit: 30, current_count: 5, remaining: 25, ...}}

  """

  require Logger
  require Nostrum.Snowflake
  require Ash.Query

  alias Nostrum.Snowflake
  alias TetoBot.Accounts

  # Configuration - loaded at compile time
  @config Application.compile_env(:teto_bot, __MODULE__, [])
  @free_user_daily_limit Keyword.get(@config, :free_user_daily_limit, 10)
  @voted_user_daily_limit Keyword.get(@config, :voted_user_daily_limit, 30)

  # Client API

  @spec allow?(Snowflake.t()) :: {:ok, boolean()} | {:error, term()}
  @doc """
  Checks if a user is allowed to send a message based on their daily limit and voting status.

  ## Examples

      TetoBot.UserRateLimiter.allow?(123456789)
      #=> {:ok, true}

      # After reaching daily limit...
      TetoBot.UserRateLimiter.allow?(123456789)
      #=> {:ok, false}

  """
  def allow?(user_id) when Snowflake.is_snowflake(user_id) do
    case get_or_create_user(user_id) do
      {:ok, user} ->
        case Ash.load(user, [:total_daily_messages, :is_voted_user]) do
          {:ok, loaded_user} ->
            daily_limit =
              if loaded_user.is_voted_user,
                do: @voted_user_daily_limit,
                else: @free_user_daily_limit

            current_count = loaded_user.total_daily_messages || 0

            Logger.debug(
              "User #{user_id} has sent #{current_count}/#{daily_limit} messages today"
            )

            if current_count < daily_limit do
              {:ok, true}
            else
              if Application.get_env(:teto_bot, :env) == :dev do
                # Bypass rate limit in dev
                {:ok, true}
              else
                Logger.debug(
                  "User #{user_id} has reached daily limit (#{current_count}/#{daily_limit})"
                )

                {:ok, false}
              end
            end

          {:error, reason} ->
            Logger.error("Failed to load user data for #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def allow?(_), do: {:error, :invalid_user_id}

  @spec record_vote(Snowflake.t()) :: :ok | {:error, term()}
  @doc """
  Records when a user votes for the bot.

  ## Examples

      TetoBot.UserRateLimiter.record_vote(123456789)
      #=> :ok

  """
  def record_vote(user_id) when Snowflake.is_snowflake(user_id) do
    case get_or_create_user(user_id) do
      {:ok, user} ->
        now = DateTime.utc_now()

        case user
             |> Ash.Changeset.for_update(:update, %{last_voted_at: now})
             |> Ash.update() do
          {:ok, _} ->
            Logger.info("Recorded vote for user #{user_id} at #{now}")
            :ok

          {:error, reason} ->
            Logger.error("Failed to record vote for user #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def record_vote(_), do: {:error, :invalid_user_id}

  @spec get_user_status(Snowflake.t()) :: {:ok, map()} | {:error, term()}
  @doc """
  Gets a user's current rate limit status.

  Returns a map with:
  - `daily_limit`: Maximum messages per day
  - `current_count`: Messages sent today
  - `remaining`: Messages remaining today
  - `has_voted_today`: Whether user voted today
  - `is_voted_user`: Whether user has voting benefits

  ## Examples

      TetoBot.UserRateLimiter.get_user_status(123456789)
      #=> {:ok, %{daily_limit: 30, current_count: 5, remaining: 25, has_voted_today: true, is_voted_user: true}}

  """
  def get_user_status(user_id) when Snowflake.is_snowflake(user_id) do
    case get_or_create_user(user_id) do
      {:ok, user} ->
        case Ash.load(user, [:total_daily_messages, :is_voted_user, :has_voted_today]) do
          {:ok, loaded_user} ->
            daily_limit =
              if loaded_user.is_voted_user,
                do: @voted_user_daily_limit,
                else: @free_user_daily_limit

            current_count = loaded_user.total_daily_messages || 0
            remaining = max(0, daily_limit - current_count)

            {:ok,
             %{
               daily_limit: daily_limit,
               current_count: current_count,
               remaining: remaining,
               has_voted_today: loaded_user.has_voted_today,
               is_voted_user: loaded_user.is_voted_user
             }}

          {:error, reason} ->
            Logger.error("Failed to load user calculations for #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_user_status(_), do: {:error, :invalid_user_id}

  @doc """
  Returns the current configuration for rate limiting.
  """
  def get_config do
    %{
      free_user_daily_limit: @free_user_daily_limit,
      voted_user_daily_limit: @voted_user_daily_limit
    }
  end

  # Private functions

  defp get_or_create_user(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, nil} ->
        case Accounts.create_user(user_id) do
          {:ok, user} -> {:ok, user}
          {:error, reason} -> {:error, reason}
        end

      {:ok, user} ->
        {:ok, user}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
