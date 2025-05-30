defmodule TetoBot.Leaderboards do
  @moduledoc """
  Manages leaderboard operations for a Discord bot, handling user intimacy scores,
  cooldowns for commands, and last interaction timestamps using Redis for persistence.

  This module provides functionality to:
  - Retrieve and update user intimacy scores in guild leaderboards.
  - Manage cooldowns for the `/feed` command.
  - Track user interactions for activity decay calculations.

  All operations interact with Redis using the `Redix` client, and errors are handled
  according to Elixir's "let it crash" philosophy, with appropriate error logging and
  user-friendly responses.

  ## Redis Keys
  - `leaderboard:<guild_id>`: Sorted set storing user IDs and their intimacy scores.
  - `updated_users:<guild_id>`: Set of user IDs marked for syncing.
  - `feed_cooldown:<guild_id>:<user_id>`: Key for tracking `/feed` command cooldowns.
  - `last_interaction:<guild_id>:<user_id>`: Key storing the timestamp of a user's last interaction.

  ## Dependencies
  - `Redix` for Redis operations.
  - `Logger` for error logging.
  """

  @feed_cooldown_duration 24 * 60 * 60

  require Logger

  @spec get_intimacy(integer(), integer()) ::
          {:ok, integer()} | {:error, Redix.ConnectionError.t()} | {:error, Redix.Error.t()}
  @doc """
  Retrieves a user's intimacy score from a guild's leaderboard.
  Returns 0 if the user is not on the leaderboard.
  Logs Redis errors if they occur.

  ## Examples
      iex> TetoBot.Leaderboards.get_intimacy(12345, 67890)
      {:ok, 100}

      iex> TetoBot.Leaderboards.get_intimacy(12345, 99999)
      {:ok, 0}
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

  @spec increment_intimacy!(integer(), integer(), integer()) :: :ok
  @doc """
  Increments a user's intimacy score in a guild's leaderboard and marks them for syncing.
  Performs an atomic operation to update the leaderboard, mark the user for syncing, and
  record their last interaction timestamp.

  ## Side Effects
  - Updates the `last_interaction:<guild_id>:<user_id>` key with the current timestamp,
    used by `TetoBot.Leaderboards.Decay` to track user activity.

  ## Examples
      iex> TetoBot.Leaderboards.increment_intimacy!(12345, 67890, 10)
      :ok
  """
  def increment_intimacy!(guild_id, user_id, increment) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    leaderboard_key = "leaderboard:#{guild_id_str}"
    updated_users_key = "updated_users:#{guild_id_str}"

    Redix.pipeline!(:redix, [
      ["ZINCRBY", leaderboard_key, Integer.to_string(increment), user_id_str],
      ["SADD", updated_users_key, user_id_str],
      get_interaction_update_command(guild_id, user_id)
    ])

    :ok
  end

  @spec check_feed_cooldown(integer(), integer()) ::
          {:ok, :allowed} | {:error, integer()} | {:error, atom()}
  @doc """
  Checks if a user can use the `/feed` command in a guild and sets a 24-hour cooldown if allowed.
  Updates the user's last interaction timestamp when the command is permitted.

  ## Side Effects
  - Sets the `feed_cooldown:<guild_id>:<user_id>` key with a 24-hour expiration when allowed.
  - Updates the `last_interaction:<guild_id>:<user_id>` key with the current timestamp,
    used by `TetoBot.Leaderboards.Decay` to track user activity.

  ## Examples
      iex> TetoBot.Leaderboards.check_feed_cooldown!(12345, 67890)
      {:ok, :allowed}

      iex> TetoBot.Leaderboards.check_feed_cooldown!(12345, 67890)
      {:error, 86300}
  """
  def check_feed_cooldown(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    cooldown_key = "feed_cooldown:#{guild_id_str}:#{user_id_str}"

    case Redix.command(:redix, ["GET", cooldown_key]) do
      {:ok, nil} ->
        {:ok, :allowed}

      {:ok, timestamp_str} ->
        case Integer.parse(timestamp_str) do
          {timestamp, _} ->
            now = System.system_time(:second)
            time_since = now - timestamp

            if time_since >= @feed_cooldown_duration do
              {:ok, :allowed}
            else
              time_left = @feed_cooldown_duration - time_since
              {:error, time_left}
            end

          :error ->
            {:error, :invalid_timestamp}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def set_feed_cooldown!(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    cooldown_key = "feed_cooldown:#{guild_id_str}:#{user_id_str}"

    Redix.pipeline!(:redix, [
      ["SET", cooldown_key, System.system_time(:second)],
      ["EXPIRE", cooldown_key, @feed_cooldown_duration]
    ])
  end

  @spec update_last_interaction(integer(), integer()) ::
          :ok | {:error, atom() | Redix.Error.t() | Redix.ConnectionError.t()}
  @doc """
  Updates the last interaction timestamp for a user in a guild.
  Should be called when a user chats or uses the `/feed` command to track activity.

  ## Side Effects
  - Updates the `last_interaction:<guild_id>:<user_id>` key with the current timestamp.
  - Logs an error if the Redis operation fails.

  ## Examples
      iex> TetoBot.Leaderboards.update_last_interaction(12345, 67890)
      :ok
  """
  def update_last_interaction(guild_id, user_id) do
    cmd = get_interaction_update_command(guild_id, user_id)

    case Redix.command(:redix, cmd) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to update last interaction for user #{user_id} in guild #{guild_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @spec get_interaction_update_command(integer(), integer()) :: [String.t()]
  @doc """
  Generates a Redis command to update the last interaction timestamp for a user in a guild.
  Used internally for atomic pipeline operations.

  ## Examples
      iex> TetoBot.Leaderboards.get_interaction_update_command(12345, 67890)
      ["SET", "last_interaction:12345:67890", "16970512340000"]
  """
  def get_interaction_update_command(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    interaction_key = "last_interaction:#{guild_id_str}:#{user_id_str}"
    timestamp = System.system_time(:millisecond)

    ["SET", interaction_key, timestamp]
  end
end
