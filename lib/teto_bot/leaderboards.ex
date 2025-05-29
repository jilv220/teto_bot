defmodule TetoBot.Leaderboards do
  @doc """
  Retrieves a user's intimacy score from a guild's leaderboard.

  ## Parameters
  - guild_id: The guild's ID (integer).
  - user_id: The user's ID (integer).

  ## Returns
  - `{:ok, intimacy}` if the score is found, where `intimacy` is an integer.
  - `{:ok, 0}` if the user is not in the leaderboard.
  - `{:error, reason}` if a Redis error occurs.

  ## Examples
  - `{:ok, 123}` for a user with 123 intimacy.
  - `{:ok, :redix}` if Redis fails.
  """
  def get_intimacy(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    leaderboard_key = "leaderboard:#{guild_id_str}"

    case Redix.command(:redix, ["ZSCORE", leaderboard_key, user_id_str]) do
      {:ok, nil} ->
        {:ok, 0}

      {:ok, score_str} ->
        # ZSCORE returns a string float.
        case Float.parse(score_str) do
          {score, _} -> {:ok, trunc(score)}
          :error -> {:error, :invalid_score}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Increments a user's intimacy in a guild's leaderboard by the specified amount and marks them for syncing.

  ## Parameters
  - guild_id: The guild's Discord ID (integer).
  - user_id: The user's Discord ID (integer).
  - increment: The amount to increase intimacy by (integer).

  ## Returns
  - :ok on success.

  ## Raises
  - `Redix.ConnectionError`: If the Redis server is unreachable or the connection fails.
  - `Redix.Error`: If the Redis commands (`ZINCRBY` or `SADD`) fail due to invalid arguments or server issues.
  """
  def increment_intimacy!(guild_id, user_id, increment) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    leaderboard_key = "leaderboard:#{guild_id_str}"
    updated_users_key = "updated_users:#{guild_id_str}"

    Redix.pipeline!(:redix, [
      ["ZINCRBY", leaderboard_key, Integer.to_string(increment), user_id_str],
      ["SADD", updated_users_key, user_id_str]
    ])

    :ok
  end

  @doc """
  Checks if a user can use the /feed command in a guild and sets the cooldown if allowed.

  ## Parameters
  - guild_id: The guild's Discord ID (integer).
  - user_id: The user's Discord ID (integer).

  ## Returns
  - `{:ok, :allowed}` if the user can use /feed.
  - `{:error, time_left}` if the cooldown is active, where `time_left` is the seconds until reset.
  - `{:error, reason}` if a Redis error occurs.

  ## Raises
  - `Redix.ConnectionError`: If the Redis server is unreachable.
  - `Redix.Error`: If Redis commands fail.

  ## Examples
      iex> TetoBot.Leaderboard.check_feed_cooldown(12345, 67890)
      {:ok, :allowed}
  """
  def check_feed_cooldown(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    cooldown_key = "feed_cooldown:#{guild_id_str}:#{user_id_str}"

    # 24 hours in seconds
    cooldown_duration = 24 * 60 * 60

    case Redix.command(:redix, ["GET", cooldown_key]) do
      {:ok, nil} ->
        set_cooldown(cooldown_key, cooldown_duration)
        {:ok, :allowed}

      {:ok, timestamp_str} ->
        case Integer.parse(timestamp_str) do
          {timestamp, _} ->
            now = System.system_time(:second)
            time_since = now - timestamp

            if time_since >= cooldown_duration do
              set_cooldown(cooldown_key, cooldown_duration)
              {:ok, :allowed}
            else
              time_left = cooldown_duration - time_since
              {:error, time_left}
            end

          :error ->
            {:error, :invalid_timestamp}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp set_cooldown(cooldown_key, cooldown_duration) do
    timestamp = System.system_time(:second)

    Redix.pipeline!(:redix, [
      ["SET", cooldown_key, timestamp],
      ["EXPIRE", cooldown_key, cooldown_duration]
    ])
  end
end
