defmodule TetoBot.RateLimiter do
  @moduledoc """
  ETS-based rate limiter for controlling user request frequency.

  Uses a sliding window approach with ETS for fast, in-memory rate limiting.
  Each user has a separate counter that resets after the configured window period.

  ## Configuration

  Configure in your application config:

      config :teto_bot,
        rate_limit_window: 60,        # seconds
        rate_limit_max_requests: 5    # max requests per window

  ## Usage

      TetoBot.RateLimiter.allow?(user_id)
      #=> true | false

  """

  use GenServer

  require Nostrum.Snowflake
  require Logger
  alias Nostrum.Snowflake

  @table_name __MODULE__
  # Clean up expired entries every 30 seconds
  @cleanup_interval 30_000

  # Client API

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec allow?(Snowflake.t()) :: boolean()
  @doc """
  Checks if a user is allowed to make a request based on rate limiting rules.

  ## Examples

      TetoBot.RateLimiter.allow?(123456789)
      #=> true

      # After multiple rapid requests...
      TetoBot.RateLimiter.allow?(123456789)
      #=> false

  """
  def allow?(user_id) when Snowflake.is_snowflake(user_id) do
    window = get_window_seconds()
    max_requests = get_max_requests()
    now = current_timestamp()

    case :ets.lookup(@table_name, user_id) do
      [] ->
        handle_first_request(user_id, now)

      [{^user_id, count, last_reset}] ->
        handle_existing_user(user_id, count, last_reset, now, window, max_requests)
    end
  end

  # Guard against invalid user_id
  def allow?(_), do: false

  defp handle_first_request(user_id, now) do
    :ets.insert(@table_name, {user_id, 1, now})
    true
  end

  defp handle_existing_user(user_id, count, last_reset, now, window, max_requests) do
    if expired?(last_reset, now, window) do
      reset_user_window(user_id, now)
    else
      check_rate_limit(user_id, count, max_requests)
    end
  end

  defp reset_user_window(user_id, now) do
    :ets.insert(@table_name, {user_id, 1, now})
    true
  end

  defp check_rate_limit(user_id, count, max_requests) do
    if count < max_requests do
      :ets.update_counter(@table_name, user_id, {2, 1})
      true
    else
      false
    end
  end

  @doc """
  Gets the current request count for a user (useful for debugging/monitoring).
  """
  @spec get_user_count(Snowflake.t()) :: {integer(), integer()} | nil
  def get_user_count(user_id) when Snowflake.is_snowflake(user_id) do
    case :ets.lookup(@table_name, user_id) do
      [{^user_id, count, last_reset}] -> {count, last_reset}
      [] -> nil
    end
  end

  @doc """
  Manually reset a user's rate limit (useful for admin commands).
  """
  @spec reset_user(Snowflake.t()) :: :ok
  def reset_user(user_id) when Snowflake.is_snowflake(user_id) do
    :ets.delete(@table_name, user_id)
    :ok
  end

  @doc """
  Get statistics about the rate limiter.
  """
  @spec stats() :: %{total_users: integer(), table_size: integer()}
  def stats do
    info = :ets.info(@table_name)

    %{
      total_users: info[:size],
      table_size: info[:memory] * :erlang.system_info(:wordsize)
    }
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table with read_concurrency for better performance
    table =
      :ets.new(@table_name, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info(":ets table initialized")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp get_window_seconds do
    Application.get_env(:teto_bot, :rate_limit_window, 60)
  end

  defp get_max_requests do
    Application.get_env(:teto_bot, :rate_limit_max_requests, 5)
  end

  defp current_timestamp do
    DateTime.utc_now() |> DateTime.to_unix(:second)
  end

  defp expired?(last_reset, now, window) do
    now - last_reset > window
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_entries do
    now = current_timestamp()
    window = get_window_seconds()

    # Get all entries and filter expired ones
    expired_users =
      @table_name
      |> :ets.tab2list()
      |> Enum.filter(fn {_user_id, _count, last_reset} ->
        expired?(last_reset, now, window)
      end)
      |> Enum.map(fn {user_id, _count, _last_reset} -> user_id end)

    # Delete expired entries
    Enum.each(expired_users, fn user_id ->
      :ets.delete(@table_name, user_id)
    end)

    if length(expired_users) > 0 do
      Logger.debug("Cleaned up #{length(expired_users)} expired rate limit entries")
    end
  end
end
