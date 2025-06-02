defmodule TetoBot.Intimacy do
  @moduledoc """
  Manages Intimacy for the bot, handling user intimacy scores,
  cooldowns for commands, and last interaction timestamps.

  This module provides functionality to:
  - Retrieve and update user intimacy scores in guild leaderboards.
  - Manage cooldowns for the `/feed` command.
  - Track user interactions for activity decay calculations.

  ## Configuration

  The feed cooldown duration can be configured in your application config:

      config :teto_bot, TetoBot.Intimacy,
        feed_cooldown_duration: :timer.hours(24)
  """
  import Ecto.Query

  alias TetoBot.Repo
  alias TetoBot.Users.UserGuild
  alias TetoBot.Users

  require Logger

  @spec get(integer(), integer()) ::
          {:ok, integer()} | {:error, term()}
  @doc """
  Retrieves a user's intimacy score from a guild's leaderboard.
  Returns 0 if the user is not on the leaderboard.
  Logs database errors if they occur.

  ## Examples
      iex> TetoBot.Intimacy.get(12345, 67890)
      {:ok, 100}

      iex> TetoBot.Intimacy.get(12345, 99999)
      {:ok, 0}
  """
  def get(guild_id, user_id) do
    try do
      case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
        nil ->
          {:ok, 0}

        %UserGuild{intimacy: score} ->
          {:ok, score}
      end
    rescue
      error ->
        Logger.error(
          "Failed to get intimacy score for guild #{guild_id}, user #{user_id}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @spec increment(integer(), integer(), integer()) :: :ok
  @doc """
  Increments a user's intimacy score in a guild's leaderboard.
  Performs an atomic operation to update the intimacy score and record the user's last interaction timestamp.

  Creates a new user_guild record if the user doesn't have one for this guild yet.

  ## Side Effects
  - Updates the user's last interaction timestamp via `TetoBot.Users.update_last_interaction!/2`

  ## Examples
      iex> TetoBot.Intimacy.increment(12345, 67890, 10)
      :ok
  """
  def increment(guild_id, user_id, increment) do
    now = DateTime.utc_now()

    case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
      nil ->
        # Create the user_guild record with intimacy score and last_interaction
        Users.update_last_interaction(guild_id, user_id)

        from(ug in UserGuild,
          where: ug.guild_id == ^guild_id and ug.user_id == ^user_id
        )
        |> Repo.update_all(set: [intimacy: increment, last_interaction: now])

      %UserGuild{intimacy: current_score} ->
        from(ug in UserGuild,
          where: ug.guild_id == ^guild_id and ug.user_id == ^user_id
        )
        |> Repo.update_all(set: [intimacy: current_score + increment, last_interaction: now])
    end

    :ok
  end

  @spec get_leaderboard(integer(), integer()) :: {:ok, list()} | {:error, term()}
  @doc """
  Gets the top N users for a guild's intimacy leaderboard.

  ## Examples
      iex> TetoBot.Intimacy.get_leaderboard(12345, 10)
      {:ok, [%{user_id: 67890, score: 150}, %{user_id: 11111, score: 100}]}
  """
  def get_leaderboard(guild_id, limit \\ 10) do
    try do
      leaderboard =
        from(ug in UserGuild,
          where: ug.guild_id == ^guild_id,
          order_by: [desc: ug.intimacy],
          limit: ^limit,
          select: %{
            user_id: ug.user_id,
            intimacy: ug.intimacy,
            last_interaction: ug.last_interaction
          }
        )
        |> Repo.all()

      {:ok, leaderboard}
    rescue
      error ->
        Logger.error("Failed to get leaderboard for guild #{guild_id}: #{inspect(error)}")
        {:error, error}
    end
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

    next_tier_intimacy_entry =
      if curr_intimacy_idx == 0 do
        # Already at highest tier, return same tier
        {intimacy, curr_intimacy_tier}
      else
        intimacy_list |> Enum.at(curr_intimacy_idx - 1)
      end

    {{intimacy, curr_intimacy_tier}, next_tier_intimacy_entry}
  end

  @doc """
  Gets all users in a guild that need their intimacy scores decayed based on inactivity.
  This can be used for background jobs to reduce intimacy over time.
  """
  @spec get_inactive_users(integer(), integer()) :: {:ok, list()} | {:error, term()}
  def get_inactive_users(guild_id, days_inactive \\ 7) do
    try do
      cutoff_date = DateTime.utc_now() |> DateTime.add(-days_inactive * 24 * 60 * 60, :second)

      inactive_users =
        from(ug in UserGuild,
          where: ug.guild_id == ^guild_id,
          where: ug.last_interaction < ^cutoff_date or is_nil(ug.last_interaction),
          where: ug.intimacy > 0,
          select: %{
            user_id: ug.user_id,
            intimacy: ug.intimacy,
            last_interaction: ug.last_interaction
          }
        )
        |> Repo.all()

      {:ok, inactive_users}
    rescue
      error ->
        Logger.error("Failed to get inactive users for guild #{guild_id}: #{inspect(error)}")
        {:error, error}
    end
  end
end
