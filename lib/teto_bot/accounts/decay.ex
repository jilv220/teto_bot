defmodule TetoBot.Accounts.Decay do
  @moduledoc """
  Provides utility functions for the intimacy decay process and its configuration.

  The actual periodic decay of intimacy scores is performed by `TetoBot.Accounts.DecayWorker`,
  an Oban worker. This module supplies the core logic (`perform_decay_check_logic/1`)
  that the worker executes.

  Additionally, this module offers:
  -   Manual triggering of the decay process (`trigger/0`), which enqueues a job for the worker.

  ## Configuration

  The behavior of the intimacy decay system is controlled by settings in the
  application environment, typically configured in `config/config.exs` or related
  environment-specific files. These settings define thresholds for inactivity,
  the amount of decay, and the minimum score.

  Example configuration (typically in `config/config.exs`):

      config :teto_bot, TetoBot.Accounts.Decay,
        inactivity_threshold: :timer.hours(24 * 3), # 3 days
        decay_amount: 5,
        minimum_intimacy: 5

  Key configuration parameters (loaded at application start/deployment):
  -   `:inactivity_threshold`: Duration of inactivity before decay applies.
  -   `:decay_amount`: Points subtracted per decay cycle.
  -   `:minimum_intimacy`: Floor for intimacy scores after decay.

  The decay process involves:
  1. Identifying inactive users based on their last interaction time.
  2. Calculating the new intimacy score.
  3. Updating the user's intimacy score directly in the primary database (Postgres)
     for the respective guild using Ecto.

  These settings are loaded by `TetoBot.Accounts.DecayWorker` from the application
  environment when it performs a job. Runtime configuration updates are not supported
  through this module; changes require a deployment or application restart.
  """

  require Logger
  import Ecto.Query

  alias TetoBot.Guilds
  alias Oban

  alias TetoBot.Repo
  alias TetoBot.Accounts.UserGuild
  alias TetoBot.Accounts.DecayWorker

  @doc """
  Manually enqueues an intimacy decay job for `TetoBot.Accounts.DecayWorker`.

  The worker will use the decay configuration loaded from the application
  environment at the time of its execution.
  """
  def trigger do
    %{}
    |> DecayWorker.new()
    |> Oban.insert()
  end

  # Public Functions for Worker / Manual Triggering
  @doc """
  Performs the intimacy decay logic based on the provided `config` map.

  This function iterates through all known guilds, identifies members eligible
  for decay based on the configuration, and applies the decay to their
  intimacy scores stored in the Postgres database via Ecto.

  It is primarily called by `TetoBot.Accounts.DecayWorker`.
  """
  def perform_decay_check_logic(config) do
    Logger.info("Starting intimacy decay check (logic invoked)")

    case Guilds.guild_ids() do
      {:ok, guild_ids} ->
        Enum.each(guild_ids, &process_guild_decay(&1, config))
        Logger.info("Completed decay check (logic invoked) for #{length(guild_ids)} guilds")

      {:error, reason} ->
        Logger.error("Failed to get guild_ids: #{inspect(reason)}")
    end
  end

  # Private Helper Functions

  defp process_guild_decay(guild_id, config) do
    case Guilds.members(guild_id: guild_id) do
      {:ok, members} ->
        inactive_members = filter_inactive_members(members, config)
        apply_decay_to_members(guild_id, inactive_members, config)

        log_decay_completion(guild_id, members, inactive_members)

      {:error, reason} ->
        Logger.error("Failed to process decay for guild #{guild_id}: #{inspect(reason)}")
    end
  end

  defp filter_inactive_members(members, config) do
    current_time = System.system_time(:millisecond)
    threshold = current_time - config.inactivity_threshold

    Enum.filter(members, fn member ->
      member.intimacy >= config.minimum_intimacy &&
        user_inactive?(member, threshold)
    end)
  end

  @doc false
  # User is inactive if `:last_message_at` or `:last_feed` is less than threshold
  defp user_inactive?(member, threshold) do
    case [member.last_message_at, member.last_feed] |> Enum.reject(&is_nil/1) do
      [] ->
        # If both interaction timestamps are nil, the user is considered inactive.
        true

      interactions ->
        # Find the most recent interaction time.
        last_interaction = Enum.max(interactions)
        # Compare the most recent interaction time against the inactivity threshold.
        DateTime.to_unix(last_interaction, :millisecond) < threshold
    end
  end

  defp log_decay_completion(guild_id, members, inactive_members) do
    if length(inactive_members) > 0 do
      Logger.info(
        "Decay process completed for guild #{guild_id}. Checked #{length(members)} members, found #{length(inactive_members)} potentially inactive."
      )
    end
  end

  # apply_decay_to_members/3: Updates intimacy scores in Postgres via Ecto.
  # Calculates new intimacy and, if changed, updates the UserGuild record.
  defp apply_decay_to_members(_guild_id, [], _config), do: :ok

  defp apply_decay_to_members(guild_id, inactive_members, config) do
    updates_count =
      inactive_members
      |> Enum.map(&process_member_decay(guild_id, &1, config))
      |> Enum.count(& &1)

    log_update_results(guild_id, updates_count)
  end

  defp process_member_decay(
         guild_id,
         %UserGuild{user_id: user_id, intimacy: current_intimacy},
         config
       ) do
    new_intimacy = max(current_intimacy - config.decay_amount, config.minimum_intimacy)

    case new_intimacy == current_intimacy do
      # No update needed
      true -> false
      false -> update_member_intimacy(guild_id, user_id, current_intimacy, new_intimacy)
    end
  end

  defp update_member_intimacy(guild_id, user_id, current_intimacy, new_intimacy) do
    query = from(ug in UserGuild, where: ug.guild_id == ^guild_id and ug.user_id == ^user_id)

    case Repo.update_all(query, set: [intimacy: new_intimacy, updated_at: DateTime.utc_now()]) do
      {1, _} ->
        Logger.info(
          "Ecto: Decayed intimacy for user #{user_id} in guild #{guild_id} from #{current_intimacy} to #{new_intimacy}."
        )

        true

      {0, _} ->
        Logger.warning(
          "Ecto: Failed to find UserGuild record for user #{user_id} in guild #{guild_id} during decay."
        )

        false

      {:error, reason} ->
        Logger.error(
          "Ecto: Failed to decay intimacy for user #{user_id} in guild #{guild_id}. Reason: #{inspect(reason)}"
        )

        false
    end
  end

  defp log_update_results(guild_id, updates_count) do
    message =
      case updates_count do
        0 -> "Ecto: No users required intimacy updates in guild #{guild_id} after filtering."
        count -> "Ecto: Successfully updated intimacy for #{count} users in guild #{guild_id}."
      end

    Logger.info(message)
    :ok
  end

  def validate_positive_integer(value, _key) when is_integer(value) and value > 0, do: :ok

  def validate_positive_integer(value, key),
    do: {:error, "Invalid #{key}: must be a positive integer, got #{inspect(value)}"}
end
