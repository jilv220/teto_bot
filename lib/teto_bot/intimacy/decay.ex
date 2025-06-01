defmodule TetoBot.Intimacy.Decay do
  @moduledoc """
  Provides utility functions for the intimacy decay process and its configuration.

  The actual periodic decay of intimacy scores is performed by `TetoBot.Intimacy.DecayWorker`,
  an Oban worker. This module supplies the core logic (`perform_decay_check_logic/1`)
  that the worker executes.

  Additionally, this module offers:
  -   Manual triggering of the decay process (`trigger_decay/0`), which enqueues a job for the worker.
  -   A function to retrieve (`get_config/0`) the decay parameters from the application
      environment.

  ## Configuration

  The behavior of the intimacy decay system is controlled by settings in the
  application environment, typically configured in `config/config.exs` or related
  environment-specific files. These settings define thresholds for inactivity,
  the amount of decay, and the minimum score.

  Example configuration (typically in `config/config.exs`):

      config :teto_bot, TetoBot.Intimacy.Decay,
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

  These settings are loaded by `TetoBot.Intimacy.DecayWorker` from the application
  environment when it performs a job. Runtime configuration updates are not supported
  through this module; changes require a deployment or application restart.
  """

  require Logger
  import Ecto.Query

  alias TetoBot.Intimacy
  alias TetoBot.Users
  alias TetoBot.Guilds
  alias Oban

  alias TetoBot.Repo
  alias TetoBot.Users.UserGuild

  # Default configuration values.
  # These are used by get_config/0 if specific settings are not found in the application environment.
  # 3 days
  @default_inactivity_threshold :timer.hours(24 * 3)
  @default_decay_amount 5
  @default_minimum_intimacy 5
  # @default_check_interval is removed as it's not relevant for the worker's config.

  @doc """
  Manually enqueues an intimacy decay job for `TetoBot.Intimacy.DecayWorker`.

  The worker will use the decay configuration loaded from the application
  environment at the time of its execution.
  """
  def trigger_decay do
    %{}
    |> Intimacy.DecayWorker.new()
    |> Oban.insert()
  end

  @doc """
  Retrieves the intimacy decay configuration from the application environment.

  This function is used by `TetoBot.Intimacy.DecayWorker` to load its settings.
  It returns a map containing `:inactivity_threshold`, `:decay_amount`, and
  `:minimum_intimacy`, applying defaults if specific values are not set.
  """
  def get_config do
    app_config = Application.get_env(:teto_bot, TetoBot.Intimacy.Decay, [])

    %{
      inactivity_threshold:
        Keyword.get(app_config, :inactivity_threshold, @default_inactivity_threshold),
      decay_amount: Keyword.get(app_config, :decay_amount, @default_decay_amount),
      minimum_intimacy: Keyword.get(app_config, :minimum_intimacy, @default_minimum_intimacy)
    }
  end

  # update_config/1 function is removed.

  # Public Functions for Worker / Manual Triggering
  @doc """
  Performs the intimacy decay logic based on the provided `config` map.

  This function iterates through all known guilds, identifies members eligible
  for decay based on the configuration, and applies the decay to their
  intimacy scores stored in the Postgres database via Ecto.

  It is primarily called by `TetoBot.Intimacy.DecayWorker`.
  """
  def perform_decay_check_logic(config) do
    Logger.info("Starting intimacy decay check (logic invoked)")

    guild_ids = Guilds.ids()
    Enum.each(guild_ids, &process_guild_decay(&1, config))
    Logger.info("Completed decay check (logic invoked) for #{length(guild_ids)} guilds")
  end

  # Private Helper Functions

  defp process_guild_decay(guild_id, config) do
    # Guilds.members/1 is expected to return a list of {user_id, current_intimacy} tuples.
    # This data might originate from a cache or direct DB query depending on Guilds module.
    case Guilds.members(guild_id) do
      {:ok, members} ->
        inactive_members = filter_inactive_members(guild_id, members, config)
        # apply_decay_to_members now uses Ecto to update Postgres
        apply_decay_to_members(guild_id, inactive_members, config)

        # The log message from apply_decay_to_members is now more specific.
        # This log provides a summary for the guild.
        if length(inactive_members) > 0 do
          Logger.info(
            "Decay process completed for guild #{guild_id}. Checked #{length(members)} members, found #{length(inactive_members)} potentially inactive."
          )
        end

      {:error, reason} ->
        Logger.error("Failed to process decay for guild #{guild_id}: #{inspect(reason)}")
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
    case Users.get_last_interaction(guild_id, user_id) do
      {:error, :not_found} ->
        true

      {:ok, date_time} ->
        DateTime.to_unix(date_time, :millisecond) < threshold
    end
  end

  # apply_decay_to_members/3: Updates intimacy scores in Postgres via Ecto.
  # Calculates new intimacy and, if changed, updates the UserGuild record.
  defp apply_decay_to_members(guild_id, inactive_members, config) do
    if Enum.empty?(inactive_members) do
      Logger.debug("No inactive members to decay in guild #{guild_id}.")
      :ok
    else
      updates_count =
        inactive_members
        |> Enum.count(fn {user_id, current_intimacy} ->
          new_intimacy = max(current_intimacy - config.decay_amount, config.minimum_intimacy)

          if new_intimacy != current_intimacy do
            query =
              from(ug in UserGuild,
                where: ug.guild_id == ^guild_id and ug.user_id == ^user_id
              )

            # Update the UserGuild record in Postgres.
            case Repo.update_all(query,
                   set: [intimacy: new_intimacy, updated_at: DateTime.utc_now()]
                 ) do
              {1, _} ->
                Logger.info(
                  "Ecto: Decayed intimacy for user #{user_id} in guild #{guild_id} from #{current_intimacy} to #{new_intimacy}."
                )

                # Count this update
                true

              {0, _} ->
                Logger.warning(
                  "Ecto: Failed to find UserGuild record for user #{user_id} in guild #{guild_id} during decay."
                )

                # Not updated
                false

              {:error, reason} ->
                Logger.error(
                  "Ecto: Failed to decay intimacy for user #{user_id} in guild #{guild_id}. Reason: #{inspect(reason)}"
                )

                # Not updated
                false
            end
          else
            # Intimacy score did not change, no update needed.
            false
          end
        end)

      if updates_count > 0 do
        Logger.info(
          "Ecto: Successfully updated intimacy for #{updates_count} users in guild #{guild_id}."
        )
      else
        Logger.info(
          "Ecto: No users required intimacy updates in guild #{guild_id} after filtering."
        )
      end

      :ok
    end
  end

  def validate_positive_integer(value, _key) when is_integer(value) and value > 0, do: :ok

  def validate_positive_integer(value, key),
    do: {:error, "Invalid #{key}: must be a positive integer, got #{inspect(value)}"}
end
