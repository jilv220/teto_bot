defmodule TetoBot.Accounts do
  @moduledoc """
  The Accounts domain.

  Manages users, guild memberships, intimacy scores, and tier calculations.
  """
  use Ash.Domain

  require Ash.Query

  alias TetoBot.Accounts.{User, UserGuild, Tier, DecayWorker}

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
  Increments a user's intimacy score.
  """
  @spec increment_intimacy(integer(), integer(), integer(), keyword()) :: :ok | {:error, term()}
  def increment_intimacy(guild_id, user_id, increment, opts \\ []) do
    # Get current intimacy
    case get_intimacy(guild_id, user_id) do
      {:ok, current_intimacy} ->
        new_intimacy = current_intimacy + increment

        # Update intimacy and potentially last_message_at
        case get_membership(user_id, guild_id) do
          {:ok, nil} ->
            # Create membership if it doesn't exist
            case create_membership(user_id, guild_id) do
              {:ok, user_guild} ->
                update_attrs = %{intimacy: new_intimacy}

                update_attrs =
                  if opts[:update_message_at] do
                    Map.put(update_attrs, :last_message_at, DateTime.utc_now())
                  else
                    update_attrs
                  end

                case user_guild
                     |> Ash.Changeset.for_update(:update, update_attrs)
                     |> Ash.update() do
                  {:ok, _} -> :ok
                  error -> error
                end

              error ->
                error
            end

          {:ok, user_guild} ->
            update_attrs = %{intimacy: new_intimacy}

            update_attrs =
              if opts[:update_message_at] do
                Map.put(update_attrs, :last_message_at, DateTime.utc_now())
              else
                update_attrs
              end

            case user_guild |> Ash.Changeset.for_update(:update, update_attrs) |> Ash.update() do
              {:ok, _} -> :ok
              error -> error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  @doc """
  Checks if a user can use the feed command based on their last_feed timestamp.
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

          last_feed ->
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

      error ->
        error
    end
  end

  @doc """
  Atomically feeds Teto, setting cooldown and incrementing intimacy.
  """
  @spec feed_teto(integer(), integer(), integer()) :: {:ok, map()} | {:error, any()}
  def feed_teto(guild_id, user_id, increment) do
    # Ensure user and membership exist
    case get_membership(user_id, guild_id) do
      {:ok, nil} ->
        # Create user and membership first
        case create_membership(user_id, guild_id) do
          {:ok, user_guild} ->
            now = DateTime.utc_now()

            case user_guild
                 |> Ash.Changeset.for_update(:update, %{
                   last_feed: now,
                   intimacy: increment
                 })
                 |> Ash.update() do
              {:ok, updated_user_guild} ->
                {:ok, %{user_guild: updated_user_guild}}

              error ->
                error
            end

          error ->
            error
        end

      {:ok, user_guild} ->
        now = DateTime.utc_now()
        new_intimacy = user_guild.intimacy + increment

        case user_guild
             |> Ash.Changeset.for_update(:update, %{
               last_feed: now,
               intimacy: new_intimacy
             })
             |> Ash.update() do
          {:ok, updated_user_guild} ->
            {:ok, %{user_guild: updated_user_guild}}

          error ->
            error
        end

      error ->
        error
    end
  end

  # Delegate tier functions to the Tier module
  defdelegate get_tier_name(intimacy), to: Tier, as: :get_tier_name
  defdelegate get_tier_info(intimacy), to: Tier, as: :get_tier_info

  # Delegate decay triggering to DecayWorker
  defdelegate trigger_decay_check(), to: DecayWorker, as: :trigger
end
