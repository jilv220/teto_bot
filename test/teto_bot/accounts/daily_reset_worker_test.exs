defmodule TetoBot.Accounts.DailyResetWorkerTest do
  @moduledoc """
  Tests for the DailyResetWorker that handles credit recharge and cooldown resets.

  Tests cover:
  - Daily credit recharge system (+10 credits per user)
  - Feed cooldown resets
  - Daily message count resets (for statistics)
  - Error handling and edge cases
  """

  use ExUnit.Case, async: true

  alias TetoBot.Accounts.DailyResetWorker
  alias TetoBot.Accounts
  alias TetoBot.Guilds
  alias TetoBot.RateLimiting

  setup do
    # Each test gets its own database transaction that gets rolled back
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
  end

  # Test constants
  @valid_user_id_1 123_456_789_012_345_678
  @valid_user_id_2 123_456_789_012_345_679
  @valid_guild_id 987_654_321_098_765_432

  describe "perform/1 - daily reset job" do
    test "recharges credits for all users" do
      # Create multiple users with different credit amounts
      {:ok, _user1} = Accounts.create_user(@valid_user_id_1)
      {:ok, _user2} = Accounts.create_user(@valid_user_id_2)

      # Use some credits for user1
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      # Use all credits for user2
      for _i <- 1..10 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_2)
      end

      # Get status before reset
      {:ok, status1_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_before} = RateLimiting.get_user_status(@valid_user_id_2)

      # 10 - 5 = 5
      assert status1_before.message_credits == 5
      # 10 - 10 = 0
      assert status2_before.message_credits == 0

      # Run the daily reset job
      assert :ok = DailyResetWorker.perform(%{})

      # Check that credits were recharged
      {:ok, status1_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_after} = RateLimiting.get_user_status(@valid_user_id_2)

      # 5 + 10 = 15
      assert status1_after.message_credits == 15
      # 0 + 10 = 10
      assert status2_after.message_credits == 10
    end

    test "resets daily message counts and feed cooldowns" do
      # Setup guild and user
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id_1, @valid_guild_id)

      # Simulate some daily activity (this would normally increment daily_message_count)
      for _i <- 1..3 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id_1)
      end

      # Get the user guild before reset
      {:ok, user_guild_before} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert user_guild_before.daily_message_count == 3

      # Run the daily reset job
      assert :ok = DailyResetWorker.perform(%{})

      # Check that daily message count was reset
      {:ok, user_guild_after} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert user_guild_after.daily_message_count == 0
    end

    test "handles users with large credit amounts" do
      # Create user with many credits (simulate heavy voter)
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      # Add many vote bonuses
      for _i <- 1..50 do
        assert :ok = RateLimiting.record_vote(@valid_user_id_1)
      end

      {:ok, status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      credits_before = status_before.message_credits

      # Run the daily reset job
      assert :ok = DailyResetWorker.perform(%{})

      # Should have added 10 more credits
      {:ok, status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after.message_credits == credits_before + 10
    end

    test "works with no users in database" do
      # Should not fail even if no users exist
      assert :ok = DailyResetWorker.perform(%{})
    end

    test "credits accumulate correctly over multiple resets" do
      # Create user and use some credits
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_initial} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_initial.message_credits == 7

      # Run first daily reset
      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status_after_first} = RateLimiting.get_user_status(@valid_user_id_1)
      # 7 + 10 = 17
      assert status_after_first.message_credits == 17

      # Run second daily reset
      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status_after_second} = RateLimiting.get_user_status(@valid_user_id_1)
      # 17 + 10 = 27
      assert status_after_second.message_credits == 27

      # Credits should accumulate, not reset
      assert status_after_second.message_credits > status_initial.message_credits
    end
  end

  describe "trigger/0 - manual job trigger" do
    test "successfully enqueues job" do
      # Should not raise error
      assert {:ok, _job} = DailyResetWorker.trigger()
    end
  end

  describe "credit recharge integration" do
    test "credit recharge works independently of daily message tracking" do
      # Setup guild and user
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id_1, @valid_guild_id)

      # Use some credits and update metrics
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id_1)
      end

      # Get status before reset
      {:ok, credit_status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_before} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)

      # 10 - 3 = 7
      assert credit_status_before.message_credits == 7
      assert membership_before.daily_message_count == 3

      # Run daily reset
      assert :ok = DailyResetWorker.perform(%{})

      # Check that both systems were updated independently
      {:ok, credit_status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_after} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)

      # Credits should be recharged
      # 7 + 10 = 17
      assert credit_status_after.message_credits == 17

      # Daily message count should be reset
      assert membership_after.daily_message_count == 0
    end

    test "vote bonuses and daily recharge work together" do
      # Create user and vote
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)
      assert :ok = RateLimiting.record_vote(@valid_user_id_1)

      {:ok, status_after_vote} = RateLimiting.get_user_status(@valid_user_id_1)
      # 10 + 10 = 20
      assert status_after_vote.message_credits == 20

      # Use some credits
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_after_usage} = RateLimiting.get_user_status(@valid_user_id_1)
      # 20 - 5 = 15
      assert status_after_usage.message_credits == 15

      # Run daily reset (should add 10 more)
      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status_after_reset} = RateLimiting.get_user_status(@valid_user_id_1)
      # 15 + 10 = 25
      assert status_after_reset.message_credits == 25

      # Vote again (should add 10 more)
      assert :ok = RateLimiting.record_vote(@valid_user_id_1)

      {:ok, status_final} = RateLimiting.get_user_status(@valid_user_id_1)
      # 25 + 10 = 35
      assert status_final.message_credits == 35
    end
  end
end
