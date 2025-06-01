defmodule TetoBot.Intimacy.DecayTest do
  use TetoBot.DataCase, async: true # Assuming DataCase is appropriate

  alias TetoBot.Intimacy.Decay
  alias TetoBot.Intimacy.DecayWorker
  alias TetoBot.Application # For manipulating app env

  # Import Oban.Testing for asserting jobs are enqueued
  import Oban.Testing

  # Setup Mox for mocking dependencies
  setup :verify_on_exit!

  # Placeholder for Mox definitions needed in test_helper.exs:
  # Mox.defmock(GuildsMock, for: TetoBot.Guilds)
  # Mox.defmock(UsersMock, for: TetoBot.Users)
  # RedixMock is no longer needed for these tests.

  # Alias for Ecto interaction
  alias TetoBot.Repo
  alias TetoBot.Users.UserGuild
  alias TetoBot.Users.User # Assuming a User schema exists

  describe "TetoBot.Intimacy.Decay public functions" do
    describe "get_config/0" do
      test "returns default configuration when nothing is set in app env" do
        # Temporarily clear app env for this module to ensure defaults are tested
        current_env_config = Application.get_env(:teto_bot, Decay, [])
        Application.delete_env(:teto_bot, Decay)

        # Access private @default_... constants via function if public, or re-define here for test
        # For simplicity, assuming TetoBot.Intimacy.Decay exposes them or we redefine them for clarity
        expected_defaults = %{
          inactivity_threshold: Decay.default_inactivity_threshold(), # Accessing private @default_...
          decay_amount: Decay.default_decay_amount(),                 # by calling them as functions
          minimum_intimacy: Decay.default_minimum_intimacy()          # if they were made public for testing.
                                                                    # Or, copy values here.
        }
        # Re-define defaults here if not exposed by module:
        expected_defaults = %{
          inactivity_threshold: :timer.hours(24 * 3),
          decay_amount: 5,
          minimum_intimacy: 5
        }


        assert Decay.get_config() == expected_defaults
      after
        Application.put_env(:teto_bot, Decay, current_env_config) # Restore
      end

      test "reflects values set in Application.put_env" do
        # Store original app env to restore it later
        original_app_env = Application.get_env(:teto_bot, Decay, [])

        # Define new values to set in the app env
        new_env_values = [
          inactivity_threshold: :timer.hours(1),
          decay_amount: 1,
          minimum_intimacy: 1
        ]
        Application.put_env(:teto_bot, Decay, new_env_values)

        expected_config = %{
          inactivity_threshold: :timer.hours(1),
          decay_amount: 1,
          minimum_intimacy: 1
        }
        assert Decay.get_config() == expected_config
      after
        # Restore original application environment for Decay module
        Application.put_env(:teto_bot, Decay, original_app_env)
      end
    end

    # Tests for update_config/1 are removed as the function is deleted.

    describe "trigger_decay/0" do
      test "enqueues a DecayWorker job" do
        assert_enqueued worker: DecayWorker
        Decay.trigger_decay()
        # To be more precise, can also capture the result of trigger_decay()
        # and assert on the job details if needed, e.g., args, queue.
        # For now, just ensuring it's enqueued is a good start.
      end
    end
  end

  describe "TetoBot.Intimacy.DecayWorker.perform/1" do
    # Mocked dependencies
    # setup do
    #   redix_mock = Mox.stub_with(RedixMock, self())
    #   guilds_mock = Mox.stub_with(GuildsMock, self())
    #   users_mock = Mox.stub_with(UsersMock, self())
    #   %{redix_mock: redix_mock, guilds_mock: guilds_mock, users_mock: users_mock}
    # end
    # Note: Using Mox.stub_with in setup might be complex with async tests.
    # Prefer direct `expect` calls in each test for simplicity here.

    @tag :decay_worker
    test "perform/1 successfully decays eligible users and updates database" do
      # --- Test Data Setup ---
      # Create Users first if UserGuild has FK to Users.id
      # For simplicity, assuming user_id can be arbitrary strings for now if no FK.
      # If using a factory:
      # user_to_decay = Factory.insert(:user)
      # user_active = Factory.insert(:user)
      # user_at_min = Factory.insert(:user)
      # user_no_change = Factory.insert(:user)
      # For direct Ecto (requires User schema):
      {:ok, user_to_decay} = Repo.insert(%User{id: "user_to_decay_id", name: "Decay Me"})
      {:ok, user_active} = Repo.insert(%User{id: "user_active_id", name: "Active User"})
      {:ok, user_at_min} = Repo.insert(%User{id: "user_at_min_id", name: "Min User"})
      {:ok, user_no_change} = Repo.insert(%User{id: "user_no_change_id", name: "No Change User"})

      guild_id = "guild_decay_test"
      now = DateTime.utc_now()

      # UserGuild records
      {:ok, ug_to_decay_before} = Repo.insert(%UserGuild{guild_id: guild_id, user_id: user_to_decay.id, intimacy: 20, inserted_at: now, updated_at: now})
      {:ok, ug_active_before} = Repo.insert(%UserGuild{guild_id: guild_id, user_id: user_active.id, intimacy: 30, inserted_at: now, updated_at: now})
      {:ok, ug_at_min_before} = Repo.insert(%UserGuild{guild_id: guild_id, user_id: user_at_min.id, intimacy: 5, inserted_at: now, updated_at: now})
      {:ok, ug_no_change_before} = Repo.insert(%UserGuild{guild_id: guild_id, user_id: user_no_change.id, intimacy: 6, inserted_at: now, updated_at: now})

      # --- Configuration ---
      config_params = [
        decay_amount: 10,
        inactivity_threshold: :timer.hours(1), # 1 hour
        minimum_intimacy: 5
      ]
      Application.put_env(:teto_bot, Decay, config_params)

      # --- Mocking ---
      GuildsMock
      |> expect(:ids, fn -> [guild_id] end)
      |> expect(:members, fn ^guild_id ->
          {:ok, [
            {user_to_decay.id, ug_to_decay_before.intimacy},
            {user_active.id, ug_active_before.intimacy},
            {user_at_min.id, ug_at_min_before.intimacy},
            {user_no_change.id, ug_no_change_before.intimacy}
          ]}
        end)

      current_time_ms = System.system_time(:millisecond)
      # User to decay: last interaction 2 hours ago (inactive)
      time_inactive = DateTime.from_unix!(current_time_ms - :timer.hours(2) * 1000, :millisecond)
      # Active user: last interaction 30 minutes ago (active)
      time_active = DateTime.from_unix!(current_time_ms - :timer.minutes(30) * 1000, :millisecond)

      UsersMock
      |> expect(:get_last_interaction, fn ^guild_id, ^user_to_decay.id -> {:ok, time_inactive} end)
      |> expect(:get_last_interaction, fn ^guild_id, ^user_active.id -> {:ok, time_active} end)
      |> expect(:get_last_interaction, fn ^guild_id, ^user_at_min.id -> {:ok, time_inactive} end) # Inactive, but at min
      |> expect(:get_last_interaction, fn ^guild_id, ^user_no_change.id -> {:ok, time_inactive} end) # Inactive, but decay won't cross min in a way that changes value

      # --- Perform Action ---
      assert DecayWorker.perform(%Oban.Job{}) == :ok

      # --- Assertions ---
      ug_to_decay_after = Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_to_decay.id)
      assert ug_to_decay_after.intimacy == 10 # 20 - 10 = 10
      assert ug_to_decay_after.updated_at > ug_to_decay_before.updated_at

      ug_active_after = Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_active.id)
      assert ug_active_after.intimacy == ug_active_before.intimacy # Should not change
      assert ug_active_after.updated_at == ug_active_before.updated_at

      ug_at_min_after = Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_at_min.id)
      assert ug_at_min_after.intimacy == 5 # Already at min, 5 - 10 = -5 -> clamped to 5
      # updated_at might or might not change depending on whether an update was attempted.
      # The current logic in apply_decay_to_members only updates if new_intimacy != current_intimacy.
      # 5 (new) == 5 (current), so no DB update, so updated_at should NOT change.
      assert ug_at_min_after.updated_at == ug_at_min_before.updated_at

      ug_no_change_after = Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_no_change.id)
      assert ug_no_change_after.intimacy == 5 # 6 - 10 = -4 -> clamped to 5
      assert ug_no_change_after.updated_at > ug_no_change_before.updated_at # Value changed from 6 to 5

    after
      Application.delete_env(:teto_bot, Decay) # Clean up test config
      # Clean up DB records
      Repo.delete_all(UserGuild)
      Repo.delete_all(User)
    end

    @tag :decay_worker_config_fail
    test "worker halts if configuration is invalid" do
      Application.put_env(:teto_bot, Decay, decay_amount: -5) # Invalid config

      assert {:error, "Invalid decay_amount: must be a positive integer, got -5"} =
             DecayWorker.perform(%Oban.Job{})
    after
      Application.delete_env(:teto_bot, Decay) # Clean up
    end
  end
end
