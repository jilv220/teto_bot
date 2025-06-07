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

  @intimacy_tiers [
    {1000, "Husband"},
    {500, "Best Friend"},
    {200, "Close Friend"},
    {101, "Good Friend"},
    {51, "Friend"},
    {21, "Buddy"},
    {11, "Acquaintance"},
    {5, "Familiar Face"},
    {0, "Stranger"}
  ]
  @tier_values Map.new(@intimacy_tiers, fn {value, name} -> {name, value} end)

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

  @doc """
  Increments a user's intimacy score in a guild's leaderboard.
  Performs an atomic operation to update the intimacy score.

  By default, it does **not** update the user's last message timestamp.
  This is suitable for interactions that are not messages (e.g., using the `/feed` command).

  To also update the `last_message_at` timestamp, which should be done for actual messages,
  pass `update_message_at: true` in the options.

  ## Options
  - `update_message_at`: (boolean) When `true`, updates the `last_message_at` timestamp. Defaults to `false`.

  ## Examples
      iex> TetoBot.Intimacy.increment(12345, 67890, 10)
      :ok

      iex> TetoBot.Intimacy.increment(12345, 67890, 1, update_message_at: true)
      :ok
  """
  def increment(guild_id, user_id, increment, opts \\ []) do
    updates = [inc: [intimacy: increment]]
    atomic_update(guild_id, user_id, updates, opts)
  end

  @spec set(integer(), integer(), integer(), keyword()) :: :ok
  @doc """
  Sets a user's intimacy score to a specific value in a guild's leaderboard.
  Performs an atomic operation to update the intimacy score.

  By default, it does **not** update the user's last message timestamp.
  This is suitable for interactions that are not messages (e.g., using the `/feed` command).

  To also update the `last_message_at` timestamp, which should be done for actual messages,
  pass `update_message_at: true` in the options.

  ## Options
  - `update_message_at`: (boolean) When `true`, updates the `last_message_at` timestamp. Defaults to `false`.

  ## Examples
      iex> TetoBot.Intimacy.set(12345, 67890, 75)
      :ok

      iex> TetoBot.Intimacy.set(12345, 67890, 75, update_message_at: true)
      :ok
  """
  def set(guild_id, user_id, value, opts \\ []) do
    atomic_update(guild_id, user_id, [set: [intimacy: value]], opts)
  end

  @spec set_relationship(integer(), integer(), keyword()) ::
          :ok | {:error, :invalid_tier | :missing_options}
  @doc """
  Sets a user's intimacy score based on relationship tier or specific value.
  Useful for testing and administrative purposes.

  ## Options
  - `:tier` - Set to a specific tier name (string or atom)
  - `:to` - Set to a specific intimacy value (integer)

  ## Examples
      iex> TetoBot.Intimacy.set_relationship(12345, 67890, tier: "Friend")
      :ok

      iex> TetoBot.Intimacy.set_relationship(12345, 67890, tier: :stranger)
      :ok

      iex> TetoBot.Intimacy.set_relationship(12345, 67890, to: 75)
      :ok

      iex> TetoBot.Intimacy.set_relationship(12345, 67890, tier: "Invalid")
      {:error, :invalid_tier}
  """
  def set_relationship(guild_id, user_id, opts) do
    case get_intimacy_value_from_opts(opts) do
      {:ok, value} -> set(guild_id, user_id, value)
      {:error, error} -> {:error, error}
    end
  end

  @doc false
  defp get_intimacy_value_from_opts(opts) do
    cond do
      tier = opts[:tier] ->
        tier_name = if is_atom(tier), do: normalize_tier_atom(tier), else: tier
        get_tier_value(tier_name)

      value = opts[:to] ->
        {:ok, value}

      true ->
        {:error, :missing_options}
    end
  end

  @spec get_tier_value(String.t()) :: {:ok, integer()} | {:error, :invalid_tier}
  defp get_tier_value(tier_name) do
    case Map.get(@tier_values, tier_name) do
      nil -> {:error, :invalid_tier}
      value -> {:ok, value}
    end
  end

  defp normalize_tier_atom(tier_atom) do
    case tier_atom do
      :stranger -> "Stranger"
      :acquaintance -> "Acquaintance"
      :friend -> "Friend"
      :close_friend -> "Close Friend"
      _ -> to_string(tier_atom)
    end
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
            last_message_at: ug.last_message_at
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
    {_, intimacy_tier} =
      @intimacy_tiers
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
    curr_intimacy_idx =
      @intimacy_tiers
      |> Enum.find_index(fn {k, _v} -> intimacy >= k end)

    {_, curr_intimacy_tier} =
      @intimacy_tiers
      |> Enum.at(curr_intimacy_idx)

    next_tier_intimacy_entry =
      if curr_intimacy_idx == 0 do
        # Already at highest tier, return same tier
        {intimacy, curr_intimacy_tier}
      else
        @intimacy_tiers |> Enum.at(curr_intimacy_idx - 1)
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
          where: ug.last_message_at < ^cutoff_date or is_nil(ug.last_message_at),
          where: ug.intimacy > 0,
          select: %{
            user_id: ug.user_id,
            intimacy: ug.intimacy,
            last_message_at: ug.last_message_at
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

  # Private Helpers

  @doc false
  defp ensure_user_guild_exists(guild_id, user_id) do
    query = from(ug in UserGuild, where: ug.guild_id == ^guild_id and ug.user_id == ^user_id)

    unless Repo.exists?(query) do
      Users.update_last_message_at(guild_id, user_id)
    end
  end

  @doc false
  defp atomic_update(guild_id, user_id, updates, opts) do
    ensure_user_guild_exists(guild_id, user_id)

    now = DateTime.utc_now()

    updates =
      if Keyword.get(opts, :update_message_at, false) do
        Keyword.update(updates, :set, [last_message_at: now], fn set_opts ->
          Keyword.put(set_opts, :last_message_at, now)
        end)
      else
        updates
      end

    from(ug in UserGuild,
      where: ug.guild_id == ^guild_id and ug.user_id == ^user_id
    )
    |> Repo.update_all(updates)

    :ok
  end
end
