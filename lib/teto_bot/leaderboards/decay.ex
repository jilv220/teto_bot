defmodule TetoBot.Leaderboards.Decay do
  @moduledoc """
  A GenServer that periodically decays intimacy scores for users who haven't
  interacted with the bot (via chat or /feed) for a specified period.

  ## Configuration
  Configurable via `start_link/1` options or application environment:
      config :teto_bot, TetoBot.Leaderboards.Decay,
        check_interval: :timer.hours(12),
        inactivity_threshold: :timer.hours(24 * 3),
        decay_amount: 5,
        minimum_intimacy: 5
  """

  use GenServer
  require Logger

  # Default configuration
  @default_check_interval :timer.hours(12)
  @default_inactivity_threshold :timer.hours(24 * 3)
  @default_decay_amount 5
  @default_minimum_intimacy 5

  @doc """
  Starts the decay GenServer.

  ## Options
  - `:check_interval` - Time between decay checks (milliseconds, default: 1 hour).
  - `:inactivity_threshold` - Inactivity period before decay (milliseconds, default: 7 days).
  - `:decay_amount` - Points to subtract per decay cycle (integer, default: 5).
  - `:minimum_intimacy` - Minimum intimacy score to maintain (integer, default: 10).
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually triggers a decay check for all guilds.
  """
  def trigger_decay do
    GenServer.cast(__MODULE__, :decay_check)
  end

  @doc """
  Gets the current configuration for the decay system.
  """
  def get_config do
    GenServer.call(__MODULE__, :get_config)
  end

  @doc """
  Updates the decay configuration at runtime.
  """
  def update_config(new_config) do
    GenServer.call(__MODULE__, {:update_config, new_config})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_env(:teto_bot, TetoBot.Leaderboards.Decay, [])

    config = %{
      check_interval: Keyword.get(config, :check_interval, @default_check_interval),
      inactivity_threshold:
        Keyword.get(config, :inactivity_threshold, @default_inactivity_threshold),
      decay_amount: Keyword.get(config, :decay_amount, @default_decay_amount),
      minimum_intimacy: Keyword.get(config, :minimum_intimacy, @default_minimum_intimacy)
    }

    with :ok <- validate_positive_integer(config.check_interval, :check_interval),
         :ok <- validate_positive_integer(config.inactivity_threshold, :inactivity_threshold),
         :ok <- validate_positive_integer(config.decay_amount, :decay_amount),
         :ok <- validate_positive_integer(config.minimum_intimacy, :minimum_intimacy) do
      schedule_decay_check(config.check_interval)
      Logger.info("Intimacy decay system started with config: #{inspect(config)}")
      {:ok, config}
    else
      {:error, reason} ->
        Logger.error("Failed to start Decay GenServer: #{reason}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_config, _from, config) do
    {:reply, config, config}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, old_config) do
    updated_config = Map.merge(old_config, new_config)

    with :ok <- validate_positive_integer(updated_config.check_interval, :check_interval),
         :ok <-
           validate_positive_integer(updated_config.inactivity_threshold, :inactivity_threshold),
         :ok <- validate_positive_integer(updated_config.decay_amount, :decay_amount),
         :ok <- validate_positive_integer(updated_config.minimum_intimacy, :minimum_intimacy) do
      Logger.info("Decay config updated: #{inspect(updated_config)}")
      {:reply, :ok, updated_config}
    else
      {:error, reason} ->
        Logger.error("Failed to update config: #{reason}")
        {:reply, {:error, reason}, old_config}
    end
  end

  @impl true
  def handle_cast(:decay_check, config) do
    perform_decay_check(config)
    {:noreply, config}
  end

  @impl true
  def handle_info(:decay_check, config) do
    perform_decay_check(config)
    schedule_decay_check(config.check_interval)
    {:noreply, config}
  end

  # Private Functions

  defp schedule_decay_check(interval) do
    Process.send_after(self(), :decay_check, interval)
  end

  defp perform_decay_check(config) do
    Logger.info("Starting intimacy decay check")

    case TetoBot.Cache.Guild.ids() do
      {:ok, guild_ids} ->
        Enum.each(guild_ids, &process_guild_decay(&1, config))
        Logger.info("Completed decay check for #{length(guild_ids)} guilds")

      {:error, reason} ->
        Logger.error("Failed to get guild ids for decay check: #{inspect(reason)}")
    end
  end

  defp process_guild_decay(guild_id, config) do
    leaderboard_key = "leaderboard:#{guild_id}"

    case get_guild_members(leaderboard_key) do
      {:ok, members} ->
        inactive_members = filter_inactive_members(guild_id, members, config)
        apply_decay_to_members(guild_id, inactive_members, config)

        if length(inactive_members) > 0 do
          Logger.info(
            "Applied decay to #{length(inactive_members)} inactive members in guild #{guild_id}"
          )
        end

      {:error, reason} ->
        Logger.error("Failed to process decay for guild #{guild_id}: #{inspect(reason)}")
    end
  end

  defp get_guild_members(leaderboard_key) do
    case Redix.command(:redix, ["ZRANGE", leaderboard_key, "0", "-1", "WITHSCORES"]) do
      {:ok, members_with_scores} ->
        members =
          members_with_scores
          |> Enum.chunk_every(2)
          |> Enum.map(fn [user_id, score_str] ->
            case Integer.parse(score_str) do
              {score, _} -> {user_id, score}
              :error -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, members}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp filter_inactive_members(guild_id, members, config) do
    current_time = System.system_time(:millisecond)
    threshold = current_time - config.inactivity_threshold

    Enum.filter(members, fn {user_id, intimacy} ->
      intimacy >= config.minimum_intimacy && user_inactive?(guild_id, user_id, threshold)
    end)
  end

  defp user_inactive?(guild_id, user_id, threshold) do
    interaction_key = "last_interaction:#{guild_id}:#{user_id}"

    case Redix.command(:redix, ["GET", interaction_key]) do
      {:ok, nil} ->
        # No interaction means inactive if they have a score
        true

      {:ok, timestamp_str} ->
        case Integer.parse(timestamp_str) do
          {timestamp_millis, _} ->
            timestamp_millis < threshold

          :error ->
            # Invalid timestamp treated as inactive
            true
        end

      {:error, _reason} ->
        # Don't decay on Redis error
        false
    end
  end

  defp apply_decay_to_members(guild_id, inactive_members, config) do
    if inactive_members != [] do
      leaderboard_key = "leaderboard:#{guild_id}"
      updated_users_key = "updated_users:#{guild_id}"

      commands =
        Enum.flat_map(inactive_members, fn {user_id, current_intimacy} ->
          Logger.info("Apply decay to user #{user_id}")
          new_intimacy = max(current_intimacy - config.decay_amount, config.minimum_intimacy)

          if new_intimacy != current_intimacy do
            [
              ["ZADD", leaderboard_key, Integer.to_string(new_intimacy), user_id],
              ["SADD", updated_users_key, user_id]
            ]
          else
            []
          end
        end)

      if commands != [] do
        case Redix.pipeline(:redix, commands) do
          {:ok, _results} ->
            Logger.debug(
              "Applied decay to #{div(length(commands), 2)} users in guild #{guild_id}"
            )

          {:error, reason} ->
            Logger.error("Failed to apply decay in guild #{guild_id}: #{inspect(reason)}")
        end
      end
    end
  end

  defp validate_positive_integer(value, _key) when is_integer(value) and value > 0, do: :ok

  defp validate_positive_integer(value, key),
    do: {:error, "Invalid #{key}: must be a positive integer, got #{inspect(value)}"}
end
