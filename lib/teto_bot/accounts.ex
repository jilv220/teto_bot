defmodule TetoBot.Accounts do
  @moduledoc """
  The Accounts domain.

  Manages users, guild memberships, intimacy scores, and tier calculations.
  """
  use Ash.Domain

  require Ash.Query

  alias TetoBot.Accounts.{DailyResetWorker, DecayWorker, Tier, User, UserGuild}

  resources do
    resource User do
      define :create_user, args: [:user_id], action: :create_user
      define :get_user, args: [:user_id], action: :get_user
    end

    resource UserGuild do
      define :create_membership, args: [:user_id, :guild_id], action: :create_membership
      define :get_membership, args: [:user_id, :guild_id], action: :get_membership
      define :update_intimacy, args: [:user_id, :guild_id, :intimacy], action: :update_intimacy
      define :update_last_message, args: [:user_id, :guild_id], action: :update_last_message
      define :update_last_feed, args: [:user_id, :guild_id], action: :update_last_feed
      define :get_guild_members, args: [:guild_id], action: :get_guild_members
      define :get_inactive_members, args: [:guild_id, :threshold], action: :get_inactive_members

      define :apply_decay,
        args: [:guild_id, :decay_amount, :minimum_intimacy],
        action: :apply_decay
    end
  end

  # ===========================================================================
  # Public API - Compatibility functions for existing code
  # ===========================================================================

  @doc """
  Gets the top N users for a guild's intimacy leaderboard.
  """
  @spec get_leaderboard(integer(), integer()) :: {:ok, list()} | {:error, term()}
  def get_leaderboard(guild_id, limit \\ 10) do
    case UserGuild
         |> Ash.Query.for_read(:read)
         |> Ash.Query.filter(guild_id == ^guild_id)
         |> Ash.Query.sort(intimacy: :desc)
         |> Ash.Query.limit(limit)
         |> Ash.read() do
      {:ok, user_guilds} ->
        leaderboard =
          Enum.map(user_guilds, fn ug ->
            %{
              user_id: ug.user_id,
              intimacy: ug.intimacy,
              last_message_at: ug.last_message_at
            }
          end)

        {:ok, leaderboard}

      error ->
        error
    end
  end

  @doc """
  Retrieves a user's intimacy score.
  """
  @spec get_intimacy(integer(), integer()) :: {:ok, integer()} | {:error, term()}
  def get_intimacy(guild_id, user_id) do
    case get_membership(user_id, guild_id) do
      {:ok, nil} -> {:ok, 0}
      {:ok, user_guild} -> {:ok, user_guild.intimacy}
      error -> error
    end
  end

  @doc """
  Retrieves a user's metrics.
  """
  def get_metrics(guild_id, user_id) do
    case get_membership(user_id, guild_id) do
      {:ok, nil} -> {:ok, {0, 0}}
      {:ok, user_guild} -> {:ok, {user_guild.intimacy, user_guild.daily_message_count}}
      error -> error
    end
  end

  @doc """
  Increments a user's intimacy score.
  """
  @spec increment_intimacy(integer(), integer(), integer(), keyword()) :: :ok | {:error, term()}
  def increment_intimacy(guild_id, user_id, increment, opts \\ []) do
    with {:ok, current_intimacy} <- get_intimacy(guild_id, user_id),
         new_intimacy <- current_intimacy + increment,
         {:ok, _} <- handle_intimacy_update(guild_id, user_id, new_intimacy, opts) do
      :ok
    end
  end

  @spec handle_intimacy_update(integer(), integer(), integer(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp handle_intimacy_update(guild_id, user_id, new_intimacy, opts) do
    with {:ok, membership_result} <- ensure_membership_for_intimacy(guild_id, user_id),
         {:ok, updated_membership} <-
           apply_intimacy_update(membership_result, user_id, guild_id, new_intimacy) do
      maybe_update_last_message(updated_membership, user_id, guild_id, opts)
    end
  end

  @spec ensure_membership_for_intimacy(integer(), integer()) ::
          {:ok, :new | :existing} | {:error, term()}
  defp ensure_membership_for_intimacy(guild_id, user_id) do
    case get_membership(user_id, guild_id) do
      {:ok, nil} ->
        case create_membership(user_id, guild_id) do
          {:ok, _membership} -> {:ok, :new}
          error -> error
        end

      {:ok, _membership} ->
        {:ok, :existing}

      error ->
        error
    end
  end

  @spec apply_intimacy_update(:new | :existing, integer(), integer(), integer()) ::
          {:ok, term()} | {:error, term()}
  defp apply_intimacy_update(_membership_status, user_id, guild_id, new_intimacy) do
    update_intimacy(user_id, guild_id, new_intimacy)
  end

  @spec maybe_update_last_message(term(), integer(), integer(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp maybe_update_last_message(updated_membership, user_id, guild_id, opts) do
    if opts[:update_message_at] do
      update_last_message(user_id, guild_id)
    else
      {:ok, updated_membership}
    end
  end

  @doc """
  Checks if a user can use the feed command based on their last_feed timestamp.

  Feed cooldowns are reset to nil at midnight UTC by DailyResetWorker.
  """
  @spec check_feed_cooldown(integer(), integer()) :: {:ok, :allowed} | {:error, integer()}
  def check_feed_cooldown(guild_id, user_id) do
    case get_membership(user_id, guild_id) do
      {:ok, nil} ->
        {:ok, :allowed}

      {:ok, user_guild} ->
        case user_guild.last_feed do
          nil ->
            {:ok, :allowed}

          _timestamp ->
            now = DateTime.utc_now()
            tomorrow_start = DateTime.new!(Date.add(Date.utc_today(), 1), ~T[00:00:00], "Etc/UTC")
            time_left = DateTime.diff(tomorrow_start, now, :second)

            {:error, time_left}
        end

      error ->
        error
    end
  end

  @doc """
  Atomically feeds Teto, setting cooldown and incrementing intimacy.
  """
  @spec feed_teto(integer(), integer(), integer()) :: {:ok, map()} | {:error, any()}
  def feed_teto(guild_id, user_id, increment) do
    with {:ok, user_guild_result} <- ensure_membership_exists(guild_id, user_id),
         {:ok, updated_user_guild} <- apply_feed_update(user_guild_result, increment) do
      {:ok, %{user_guild: updated_user_guild}}
    end
  end

  @spec apply_feed_update({:new | :existing, UserGuild.t()}, integer()) ::
          {:ok, UserGuild.t()} | {:error, any()}
  defp apply_feed_update({:new, user_guild}, increment) do
    now = DateTime.utc_now()

    user_guild
    |> Ash.Changeset.for_update(:update, %{
      last_feed: now,
      intimacy: increment
    })
    |> Ash.update()
  end

  defp apply_feed_update({:existing, user_guild}, increment) do
    now = DateTime.utc_now()
    new_intimacy = user_guild.intimacy + increment

    user_guild
    |> Ash.Changeset.for_update(:update, %{
      last_feed: now,
      intimacy: new_intimacy
    })
    |> Ash.update()
  end

  @doc """
  Updates user metrics when they send a message, incrementing daily count and intimacy.

  Daily message counts are reset to 0 at midnight UTC by DailyResetWorker.
  """
  @spec update_user_metrics(integer(), integer()) :: {:ok, map()} | {:error, any()}
  def update_user_metrics(guild_id, user_id) do
    with {:ok, user_guild_result} <- ensure_membership_exists(guild_id, user_id),
         {:ok, updated_user_guild} <- update_metrics_for_existing_membership(user_guild_result) do
      {:ok, %{user_guild: updated_user_guild}}
    end
  end

  @spec ensure_membership_exists(integer(), integer()) ::
          {:ok, {:new, UserGuild.t()} | {:existing, UserGuild.t()}} | {:error, any()}
  defp ensure_membership_exists(guild_id, user_id) do
    case get_membership(user_id, guild_id) do
      {:ok, nil} -> create_new_membership_for_metrics(user_id, guild_id)
      {:ok, user_guild} -> {:ok, {:existing, user_guild}}
      error -> error
    end
  end

  @spec create_new_membership_for_metrics(integer(), integer()) ::
          {:ok, {:new, UserGuild.t()}} | {:error, any()}
  defp create_new_membership_for_metrics(user_id, guild_id) do
    case create_membership(user_id, guild_id) do
      {:ok, user_guild} -> {:ok, {:new, user_guild}}
      error -> error
    end
  end

  @spec update_metrics_for_existing_membership({:new | :existing, UserGuild.t()}) ::
          {:ok, UserGuild.t()} | {:error, any()}
  defp update_metrics_for_existing_membership({membership_type, user_guild}) do
    now = DateTime.utc_now()
    metrics = calculate_new_metrics({membership_type, user_guild})

    user_guild
    |> Ash.Changeset.for_update(:update, %{
      last_message_at: now,
      intimacy: metrics.new_intimacy,
      daily_message_count: metrics.new_daily_count
    })
    |> Ash.update()
  end

  @spec calculate_new_metrics({:new | :existing, UserGuild.t()}) :: %{
          new_intimacy: integer(),
          new_daily_count: integer()
        }
  defp calculate_new_metrics({:new, _user_guild}) do
    daily_message_count = 1
    intimacy_increment = calculate_intimacy_increment(daily_message_count)

    %{
      new_intimacy: intimacy_increment,
      new_daily_count: daily_message_count
    }
  end

  defp calculate_new_metrics({:existing, user_guild}) do
    new_daily_count = user_guild.daily_message_count + 1
    intimacy_increment = calculate_intimacy_increment(new_daily_count)
    new_intimacy = user_guild.intimacy + intimacy_increment

    %{
      new_intimacy: new_intimacy,
      new_daily_count: new_daily_count
    }
  end

  defp calculate_intimacy_increment(daily_message_count) do
    cond do
      daily_message_count <= 5 ->
        1

      # Every other message
      daily_message_count <= 15 ->
        if rem(daily_message_count, 2) == 0, do: 1, else: 0

      # Every 4th message
      true ->
        if rem(daily_message_count, 4) == 0, do: 1, else: 0
    end
  end

  # Delegate tier functions to the Tier module
  defdelegate get_tier_name(intimacy), to: Tier, as: :get_tier_name
  defdelegate get_tier_info(intimacy), to: Tier, as: :get_tier_info

  # Delegate job triggering to workers
  defdelegate trigger_decay_check(), to: DecayWorker, as: :trigger
  defdelegate trigger_daily_reset(), to: DailyResetWorker, as: :trigger
end
