defmodule TetoBot.Intimacy do
  @moduledoc """
  Manages Intimacy for the bot, handling user intimacy scores,
  cooldowns for commands, and last interaction timestamps using Redis for persistence.

  This module provides functionality to:
  - Retrieve and update user intimacy scores in guild leaderboards.
  - Manage cooldowns for the `/feed` command.
  - Track user interactions for activity decay calculations.

  All operations interact with Redis using the `Redix` client, and errors are handled
  according to Elixir's "let it crash" philosophy, with appropriate error logging and
  user-friendly responses.

  ## Configuration

  The feed cooldown duration can be configured in your application config:

      config :teto_bot, TetoBot.Intimacy,
        feed_cooldown_duration: 24 * 60 * 60  # 24 hours in seconds

  ## Redis Keys
  - `leaderboard:<guild_id>`: Sorted set storing user IDs and their intimacy scores.
  - `updated_users:<guild_id>`: Set of user IDs marked for syncing.
  - `feed_cooldown:<guild_id>:<user_id>`: Key for tracking `/feed` command cooldowns.
  - `last_interaction:<guild_id>:<user_id>`: Key storing the timestamp of a user's last interaction.

  ## Dependencies
  - `Redix` for Redis operations.
  - `Logger` for error logging.
  """

  require Logger

  @default_feed_cooldown_duration :timer.hours(24)

  defp feed_cooldown_duration do
    Application.get_env(:teto_bot, __MODULE__, [])
    |> Keyword.get(:feed_cooldown_duration, @default_feed_cooldown_duration)
    |> div(1000)
  end

  @spec get(integer(), integer()) ::
          {:ok, integer()} | {:error, Redix.ConnectionError.t()} | {:error, Redix.Error.t()}
  @doc """
  Retrieves a user's intimacy score from a guild's leaderboard.
  Returns 0 if the user is not on the leaderboard.
  Logs Redis errors if they occur.

  ## Examples
      iex> TetoBot.Intimacy.get(12345, 67890)
      {:ok, 100}

      iex> TetoBot.Intimacy.get(12345, 99999)
      {:ok, 0}
  """
  def get(guild_id, user_id) do
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

  @spec increment!(integer(), integer(), integer()) :: :ok
  @doc """
  Increments a user's intimacy score in a guild's leaderboard and marks them for syncing.
  Performs an atomic operation to update the leaderboard, mark the user for syncing, and
  record their last interaction timestamp.

  ## Side Effects
  - Updates the `last_interaction:<guild_id>:<user_id>` key with the current timestamp,
    used by `TetoBot.Intimacy.Decay` to track user activity.

  ## Examples
      iex> TetoBot.Intimacy.increment!(12345, 67890, 10)
      :ok
  """
  def increment!(guild_id, user_id, increment) do
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
  Checks if a user can use the `/feed` command in a guild and sets a cooldown if allowed.
  The cooldown duration is configurable (defaults to 24 hours).
  Updates the user's last interaction timestamp when the command is permitted.

  ## Side Effects
  - Sets the `feed_cooldown:<guild_id>:<user_id>` key with an expiration when allowed.
  - Updates the `last_interaction:<guild_id>:<user_id>` key with the current timestamp,
    used by `TetoBot.Intimacy.Decay` to track user activity.

  ## Examples
      iex> TetoBot.Intimacy.check_feed_cooldown(12345, 67890)
      {:ok, :allowed}

      iex> TetoBot.Intimacy.check_feed_cooldown(12345, 67890)
      {:error, 86300}
  """
  def check_feed_cooldown(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    cooldown_key = "feed_cooldown:#{guild_id_str}:#{user_id_str}"
    cooldown_duration = feed_cooldown_duration()

    case Redix.command(:redix, ["GET", cooldown_key]) do
      {:ok, nil} ->
        {:ok, :allowed}

      {:ok, timestamp_str} ->
        case Integer.parse(timestamp_str) do
          {timestamp, _} ->
            now = System.system_time(:second)
            time_since = now - timestamp

            if time_since >= cooldown_duration do
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

  @spec set_feed_cooldown!(integer(), integer()) :: :ok
  @doc """
  Sets the feed cooldown for a user in a guild.
  The cooldown duration is configurable (defaults to 24 hours).

  ## Examples
      iex> TetoBot.Intimacy.set_feed_cooldown!(12345, 67890)
      :ok
  """
  def set_feed_cooldown!(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    cooldown_key = "feed_cooldown:#{guild_id_str}:#{user_id_str}"
    cooldown_duration = feed_cooldown_duration()

    Redix.pipeline!(:redix, [
      ["SET", cooldown_key, System.system_time(:second)],
      ["EXPIRE", cooldown_key, cooldown_duration]
    ])

    :ok
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
      iex> TetoBot.Intimacy.update_last_interaction(12345, 67890)
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
      iex> TetoBot.Intimacy.get_interaction_update_command(12345, 67890)
      ["SET", "last_interaction:12345:67890", "16970512340000"]
  """
  def get_interaction_update_command(guild_id, user_id) do
    user_id_str = Integer.to_string(user_id)
    guild_id_str = Integer.to_string(guild_id)
    interaction_key = "last_interaction:#{guild_id_str}:#{user_id_str}"
    timestamp = System.system_time(:millisecond)

    ["SET", interaction_key, timestamp]
  end

  @spec get_tier(integer()) :: String.t()
  @doc """
  Returns the intimacy tier name for a given intimacy score.

  ## Examples
      iex> TetoBot.Intimacy.get_tier(75)
      "Friend"

      iex> TetoBot.Intimacy.get_tier(5)
      "Stranger"
  """
  def get_tier(intimacy) do
    intimacy_list = [{101, "Close Friend"}, {51, "Friend"}, {11, "Acquaintance"}, {0, "Stranger"}]

    {_, intimacy_tier} =
      intimacy_list
      |> Enum.find(fn {k, _v} -> intimacy >= k end)

    intimacy_tier
  end

  @spec get_tier_info(integer()) :: {{integer(), binary()}, {integer(), binary()}}
  @doc """
  Returns current tier information and next tier information for a given intimacy score.

  ## Examples
      iex> TetoBot.Intimacy.get_tier_info(25)
      {{25, "Acquaintance"}, {51, "Friend"}}
  """
  def get_tier_info(intimacy) do
    intimacy_list = [{101, "Close Friend"}, {51, "Friend"}, {11, "Acquaintance"}, {0, "Stranger"}]

    curr_intimacy_idx =
      intimacy_list
      |> Enum.find_index(fn {k, _v} -> intimacy >= k end)

    {_, curr_intimacy_tier} =
      intimacy_list
      |> Enum.at(curr_intimacy_idx)

    next_tier_intimacy_idx = curr_intimacy_idx - 1

    # default to highest tier if out of bound
    next_tier_intimacy_entry =
      intimacy_list
      |> Enum.at(next_tier_intimacy_idx, Enum.at(intimacy_list, 0))

    {{intimacy, curr_intimacy_tier}, next_tier_intimacy_entry}
  end
end
