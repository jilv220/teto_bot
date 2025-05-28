defmodule TetoBot.RateLimiter do
  require Nostrum.Snowflake
  alias Nostrum.Snowflake
  require Logger

  @key_prefix "rate_limit:"

  def allow?(user_id) when Snowflake.is_snowflake(user_id) do
    window = Application.get_env(:teto_bot, :rate_limit_window, 60)
    max_requests = Application.get_env(:teto_bot, :rate_limit_max_requests, 5)

    now = DateTime.utc_now() |> DateTime.to_unix(:second)
    redis_key = "#{@key_prefix}#{user_id}"

    case Redix.command(:redix, ["MGET", "#{redis_key}:count", "#{redis_key}:last_time"]) do
      {:ok, [count_str, last_time_str]} ->
        count = parse_integer(count_str, 0)
        last_time = parse_integer(last_time_str, 0)

        IO.inspect("#{count}:#{last_time}")

        if now - last_time > window do
          update_redis(redis_key, 1, now)
          true
        else
          if count < max_requests do
            update_redis(redis_key, count + 1, last_time)
            true
          else
            false
          end
        end

      {:ok, [nil, nil]} ->
        update_redis(redis_key, 1, now)
        true

      {:error, %Redix.ConnectionError{reason: reason}} ->
        Logger.error("Redis connection error in rate limiter: #{inspect(reason)}")
        # Permissive fallback to avoid blocking users
        true

      {:error, reason} ->
        Logger.error("Redis error in rate limiter: #{inspect(reason)}")
        # Permissive fallback
        true
    end
  end

  # Guard against invalid user_id
  def allow?(_), do: false

  defp update_redis(redis_key, count, last_time) do
    window = Application.get_env(:teto_bot, :rate_limit_window, 60)

    # Use a transaction to set count and last_time atomically
    Redix.pipeline(:redix, [
      ["MULTI"],
      ["SET", "#{redis_key}:count", to_string(count), "EX", window],
      ["SET", "#{redis_key}:last_time", to_string(last_time), "EX", window],
      ["EXEC"]
    ])
    |> case do
      {:ok, [_, _, _, [_count, _last_time]]} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to update rate limit in Redis: #{inspect(reason)}")
        :error
    end
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(str, default) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end
end
