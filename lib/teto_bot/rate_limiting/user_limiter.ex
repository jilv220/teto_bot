defmodule TetoBot.RateLimiting.UserLimiter do
  @moduledoc """
  User-specific rate limiter for controlling daily message limits based on voting status.

  Features:
  - Free users: limited daily messages
  - Voted users: increased daily limits
  - Daily limits reset at midnight UTC
  - Development environment bypass

  ## Configuration

  Configure via the RateLimiting context:

      config :teto_bot, TetoBot.RateLimiting,
        free_user_daily_limit: 10,
        voted_user_daily_limit: 30

  ## Examples

      TetoBot.RateLimiting.UserLimiter.allow?(user_id)
      #=> {:ok, true} | {:ok, false} | {:error, reason}

      TetoBot.RateLimiting.UserLimiter.get_user_status(user_id)
      #=> {:ok, %{daily_limit: 30, current_count: 5, remaining: 25, ...}}

  """

  require Logger
  require Ash.Query

  alias TetoBot.RateLimiting.Behaviour
  alias TetoBot.Accounts
  alias Nostrum.Snowflake

  # Default configuration
  @defaults [
    free_user_daily_limit: 10,
    voted_user_daily_limit: 30
  ]

  @type status_result ::
          {:ok,
           %{
             daily_limit: non_neg_integer(),
             current_count: non_neg_integer(),
             remaining: non_neg_integer(),
             has_voted_today: boolean(),
             is_voted_user: boolean()
           }}

  # Client API

  @spec allow?(Snowflake.t()) :: {:ok, boolean()} | {:error, term()}
  @doc """
  Checks if a user is allowed to send a message based on their daily limit and voting status.

  Bypasses rate limits in development environment.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.allow?(123456789)
      #=> {:ok, true}

      # After reaching daily limit...
      TetoBot.RateLimiting.UserLimiter.allow?(123456789)
      #=> {:ok, false}

  """
  def allow?(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      if Behaviour.bypass_dev_limits?() do
        Behaviour.log_decision("user", user_id, true, %{reason: "dev_bypass"})
        {:ok, true}
      else
        check_user_limits(user_id)
      end
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec record_vote(Snowflake.t()) :: :ok | {:error, term()}
  @doc """
  Records when a user votes for the bot.

  Updates the user's last_voted_at timestamp, which affects their daily limit tier.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.record_vote(123456789)
      #=> :ok

  """
  def record_vote(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_record_vote(user_id)
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec get_user_status(Snowflake.t()) :: status_result() | {:error, term()}
  @doc """
  Gets a user's current rate limit status.

  Returns comprehensive status information including limits, usage, and voting status.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.get_user_status(123456789)
      #=> {:ok, %{daily_limit: 30, current_count: 5, remaining: 25, has_voted_today: true, is_voted_user: true}}

  """
  def get_user_status(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_get_user_status(user_id)
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec get_config() :: %{
          free_user_daily_limit: non_neg_integer(),
          voted_user_daily_limit: non_neg_integer()
        }
  @doc """
  Returns the current configuration for rate limiting.
  """
  def get_config do
    %{
      free_user_daily_limit: Behaviour.get_config(:free_user_daily_limit, @defaults),
      voted_user_daily_limit: Behaviour.get_config(:voted_user_daily_limit, @defaults)
    }
  end

  # Private functions

  defp check_user_limits(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_data(user) do
      daily_limit = determine_daily_limit(loaded_user)
      current_count = loaded_user.total_daily_messages || 0
      allowed? = current_count < daily_limit

      Behaviour.log_decision("user", user_id, allowed?, %{
        current: current_count,
        limit: daily_limit,
        voted: loaded_user.is_voted_user
      })

      {:ok, allowed?}
    end
  end

  defp do_record_vote(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, _updated_user} <- update_user_vote(user, DateTime.utc_now()) do
      Logger.info("Recorded vote for user #{user_id}")
      :ok
    end
  end

  defp do_get_user_status(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_status_data(user) do
      daily_limit = determine_daily_limit(loaded_user)
      current_count = loaded_user.total_daily_messages || 0
      remaining = max(0, daily_limit - current_count)

      status = %{
        daily_limit: daily_limit,
        current_count: current_count,
        remaining: remaining,
        has_voted_today: loaded_user.has_voted_today,
        is_voted_user: loaded_user.is_voted_user
      }

      {:ok, status}
    end
  end

  defp get_or_create_user(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, nil} ->
        Accounts.create_user(user_id)

      {:ok, user} ->
        {:ok, user}

      {:error, reason} ->
        Logger.error("Failed to get user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_user_data(user) do
    case Ash.load(user, [:total_daily_messages, :is_voted_user]) do
      {:ok, loaded_user} ->
        {:ok, loaded_user}

      {:error, reason} ->
        Logger.error("Failed to load user data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_user_status_data(user) do
    case Ash.load(user, [:total_daily_messages, :is_voted_user, :has_voted_today]) do
      {:ok, loaded_user} ->
        {:ok, loaded_user}

      {:error, reason} ->
        Logger.error("Failed to load user status data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_user_vote(user, timestamp) do
    case user
         |> Ash.Changeset.for_update(:update, %{last_voted_at: timestamp})
         |> Ash.update() do
      {:ok, updated_user} ->
        {:ok, updated_user}

      {:error, reason} ->
        Logger.error("Failed to update user vote: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp determine_daily_limit(user) do
    if user.is_voted_user do
      Behaviour.get_config(:voted_user_daily_limit, @defaults)
    else
      Behaviour.get_config(:free_user_daily_limit, @defaults)
    end
  end
end
