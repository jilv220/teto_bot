defmodule TetoBot.Accounts do
  @moduledoc """
  Manages user accounts, intimacy, and activity tracking for the bot.

  This context is the single source of truth for all user-related data,
  including guild-specific information like intimacy scores, command cooldowns,
  and interaction timestamps. It provides a unified API for managing user
  accounts and their progression within the bot's systems.

  ## Key Features

  - User and guild account creation and management
  - Intimacy score tracking and leaderboards
  - Daily command cooldowns (e.g., for feeding Teto)
  - Atomic, transactional updates for data consistency
  - Intimacy decay for inactive users
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Nostrum.Snowflake
  alias TetoBot.Repo
  alias TetoBot.Accounts.{DecayWorker, Tier, User, UserGuild}

  require Logger

  # ===========================================================================
  # Public API - User & Guild Data
  # ===========================================================================

  @doc """
  Gets the last message timestamp for a user in a specific guild.
  """
  @spec get_last_message_at(integer(), integer()) :: {:ok, DateTime.t()} | {:error, :not_found}
  def get_last_message_at(guild_id, user_id) do
    case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
      nil -> {:error, :not_found}
      %UserGuild{last_message_at: nil} -> {:error, :not_found}
      %UserGuild{last_message_at: datetime} -> {:ok, datetime}
    end
  end

  # ===========================================================================
  # Public API - Cooldowns
  # ===========================================================================

  @doc """
  Checks if a user can use the feed command based on their last_feed timestamp.
  """
  @spec check_feed_cooldown(Snowflake.t(), Snowflake.t()) :: {:ok, :allowed} | {:error, integer()}
  def check_feed_cooldown(guild_id, user_id) do
    case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
      nil ->
        {:ok, :allowed}

      %UserGuild{last_feed: nil} ->
        {:ok, :allowed}

      %UserGuild{last_feed: last_feed} ->
        now = DateTime.utc_now()
        today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

        if DateTime.compare(last_feed, today_start) == :lt do
          {:ok, :allowed}
        else
          tomorrow_start = DateTime.add(today_start, 1, :day)
          time_left = DateTime.diff(tomorrow_start, now, :second)
          {:error, time_left}
        end
    end
  end

  # ===========================================================================
  # Public API - Intimacy
  # ===========================================================================

  @doc """
  Retrieves a user's intimacy score.
  """
  @spec get_intimacy(integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def get_intimacy(guild_id, user_id) do
    with_error_logging(
      "Failed to get intimacy score for guild #{guild_id}, user #{user_id}",
      fn ->
        case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
          nil -> {:ok, 0}
          %UserGuild{intimacy: score} -> {:ok, score}
        end
      end
    )
  end

  @doc """
  Increments a user's intimacy score.
  """
  def increment_intimacy(guild_id, user_id, increment, opts \\ []) do
    updates = [inc: [intimacy: increment]]
    atomic_update(guild_id, user_id, updates, opts)
  end

  @doc """
  Sets a user's intimacy score to a specific value.
  """
  @spec set_intimacy(integer(), integer(), integer(), keyword()) :: :ok
  def set_intimacy(guild_id, user_id, value, opts \\ []) do
    atomic_update(guild_id, user_id, [set: [intimacy: value]], opts)
  end

  @doc """
  Sets a user's intimacy score based on relationship tier or specific value.
  """
  @spec set_relationship(integer(), integer(), keyword()) ::
          :ok | {:error, :invalid_tier | :missing_options}
  def set_relationship(guild_id, user_id, opts) do
    case get_intimacy_value_from_opts(opts) do
      {:ok, value} -> set_intimacy(guild_id, user_id, value)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Gets the top N users for a guild's intimacy leaderboard.
  """
  @spec get_leaderboard(integer(), integer()) :: {:ok, list()} | {:error, term()}
  def get_leaderboard(guild_id, limit \\ 10) do
    with_error_logging("Failed to get leaderboard for guild #{guild_id}", fn ->
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
    end)
  end

  @doc """
  Atomically feeds Teto, setting cooldown and incrementing intimacy within a transaction.
  """
  @spec feed_teto(integer(), integer(), integer()) :: {:ok, map()} | {:error, any()}
  def feed_teto(guild_id, user_id, increment) do
    Multi.new()
    |> ensure_user_guild_exists_multi(guild_id, user_id)
    |> set_feed_cooldown_multi(guild_id, user_id)
    |> increment_intimacy_multi(guild_id, user_id, increment)
    |> Repo.transaction()
  end

  defdelegate get_tier_name(intimacy), to: Tier, as: :get_tier_name
  defdelegate get_tier_info(intimacy), to: Tier, as: :get_tier_info
  defdelegate trigger_decay_check(), to: DecayWorker, as: :trigger

  # ===========================================================================
  # Ecto.Multi Composers
  # ===========================================================================

  @doc """
  Adds setting the last_feed timestamp for a user to a multi.
  """
  @spec set_feed_cooldown_multi(Multi.t(), Snowflake.t(), Snowflake.t()) :: Multi.t()
  def set_feed_cooldown_multi(multi, guild_id, user_id) do
    now = DateTime.utc_now()
    query = from(ug in UserGuild, where: ug.guild_id == ^guild_id and ug.user_id == ^user_id)
    Multi.update_all(multi, :set_cooldown, query, set: [last_feed: now])
  end

  @doc """
  Adds an intimacy increment to a multi transaction.
  """
  @spec increment_intimacy_multi(Multi.t(), integer(), integer(), integer(), keyword()) ::
          Multi.t()
  def increment_intimacy_multi(multi, guild_id, user_id, increment, opts \\ []) do
    updates = [inc: [intimacy: increment]]
    atomic_update_multi(multi, guild_id, user_id, updates, opts)
  end

  @doc """
  Adds ensuring a user_guild record exists to a multi.
  """
  @spec ensure_user_guild_exists_multi(Multi.t(), Snowflake.t(), Snowflake.t()) :: Multi.t()
  def ensure_user_guild_exists_multi(multi, guild_id, user_id) do
    now = DateTime.utc_now()

    multi
    |> Multi.insert(
      :user,
      User.changeset(%User{user_id: user_id}, %{}),
      on_conflict: [set: [updated_at: now]],
      conflict_target: :user_id
    )
    |> Multi.insert(
      :user_guild,
      UserGuild.changeset(%UserGuild{}, %{user_id: user_id, guild_id: guild_id}),
      on_conflict: :nothing,
      conflict_target: [:user_id, :guild_id]
    )
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_intimacy_value_from_opts(opts) do
    cond do
      tier = opts[:tier] -> Tier.get_tier_value(tier)
      value = opts[:to] -> {:ok, value}
      true -> {:error, :missing_options}
    end
  end

  defp atomic_update(guild_id, user_id, updates, opts) do
    case Multi.new()
         |> ensure_user_guild_exists_multi(guild_id, user_id)
         |> atomic_update_multi(guild_id, user_id, updates, opts)
         |> Repo.transaction() do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp atomic_update_multi(multi, guild_id, user_id, updates, opts) do
    now = DateTime.utc_now()

    updates =
      if Keyword.get(opts, :update_message_at, false) do
        Keyword.update(updates, :set, [last_message_at: now], fn set_opts ->
          Keyword.put(set_opts, :last_message_at, now)
        end)
      else
        updates
      end

    query = from(ug in UserGuild, where: ug.guild_id == ^guild_id and ug.user_id == ^user_id)
    Multi.update_all(multi, :atomic_update, query, updates)
  end

  defp with_error_logging(message, fun) do
    try do
      fun.()
    rescue
      error ->
        Logger.error("#{message}: #{inspect(error)}")
        {:error, error}
    end
  end
end
