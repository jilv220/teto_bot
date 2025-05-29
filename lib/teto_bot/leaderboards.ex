defmodule TetoBot.Leaderboards do
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
end
