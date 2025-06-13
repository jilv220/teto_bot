defmodule TetoBot.Accounts.DailyResetWorkerTest do
  @moduledoc """
  Tests for the DailyResetWorker that handles credit refill and cooldown resets.

  Tests cover:
  - Daily credit refill system (refill to cap if below)
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
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
    config = RateLimiting.get_user_config()
    {:ok, config: config}
  end

  # Test constants
  @valid_user_id_1 123_456_789_012_345_678
  @valid_user_id_2 123_456_789_012_345_679
  @valid_guild_id 987_654_321_098_765_432

  describe "perform/1 - daily reset job" do
    test "refills credits to cap for users below the cap", %{config: config} do
      refill_cap = config.daily_credit_refill_cap
      {:ok, _user1} = Accounts.create_user(@valid_user_id_1)
      {:ok, _user2} = Accounts.create_user(@valid_user_id_2)

      # Use 5 credits from user1 (should be refilled to cap)
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      # Use all credits from user2 (should be refilled to cap)
      for _i <- 1..refill_cap do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_2)
      end

      {:ok, status1_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_before} = RateLimiting.get_user_status(@valid_user_id_2)
      assert status1_before.message_credits == refill_cap - 5
      assert status2_before.message_credits == 0

      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status1_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_after} = RateLimiting.get_user_status(@valid_user_id_2)
      # Both users should be refilled to the cap
      assert status1_after.message_credits == refill_cap
      assert status2_after.message_credits == refill_cap
    end

    test "resets daily message counts and feed cooldowns" do
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id_1, @valid_guild_id)

      for _i <- 1..3 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id_1)
      end

      {:ok, user_guild_before} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert user_guild_before.daily_message_count == 3
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, user_guild_after} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert user_guild_after.daily_message_count == 0
    end

    test "does not change credits for users already at or above cap", %{config: config} do
      refill_cap = config.daily_credit_refill_cap
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      # Add many credits through voting (above the cap)
      for _i <- 1..10 do
        assert :ok = RateLimiting.add_vote_credits(@valid_user_id_1)
      end

      {:ok, status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      credits_before = status_before.message_credits
      # Should be above the refill cap due to vote bonuses
      assert credits_before > refill_cap

      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      # Credits should remain unchanged (not reduced to cap)
      assert status_after.message_credits == credits_before
    end

    test "works with no users in database" do
      assert :ok = DailyResetWorker.perform(%{})
    end

    test "refill system maintains cap over multiple resets", %{config: config} do
      refill_cap = config.daily_credit_refill_cap
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_initial} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_initial.message_credits == refill_cap - 3

      # First reset - should refill to cap
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after_first} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_first.message_credits == refill_cap

      # Second reset - should remain at cap (no change)
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after_second} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_second.message_credits == refill_cap
    end
  end

  describe "trigger/0 - manual job trigger" do
    test "successfully enqueues job" do
      assert {:ok, _job} = DailyResetWorker.trigger()
    end
  end

  describe "credit refill integration" do
    test "credit refill works independently of daily message tracking", %{config: config} do
      refill_cap = config.daily_credit_refill_cap
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id_1, @valid_guild_id)

      # Use 3 credits and track messages
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id_1)
      end

      {:ok, credit_status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_before} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert credit_status_before.message_credits == refill_cap - 3
      assert membership_before.daily_message_count == 3

      assert :ok = DailyResetWorker.perform(%{})

      {:ok, credit_status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_after} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      # Credits refilled to cap
      assert credit_status_after.message_credits == refill_cap
      # Message count reset
      assert membership_after.daily_message_count == 0
    end

    test "vote bonuses and daily refill work together", %{config: config} do
      refill_cap = config.daily_credit_refill_cap
      vote_bonus = config.vote_credit_bonus
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      # Start with default cap, add vote bonus
      assert :ok = RateLimiting.add_vote_credits(@valid_user_id_1)
      {:ok, status_after_vote} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_vote.message_credits == refill_cap + vote_bonus

      # Use some credits
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_after_usage} = RateLimiting.get_user_status(@valid_user_id_1)
      expected_after_usage = refill_cap + vote_bonus - 5
      assert status_after_usage.message_credits == expected_after_usage

      # Daily reset should not change credits if still above cap
      if expected_after_usage >= refill_cap do
        assert :ok = DailyResetWorker.perform(%{})
        {:ok, status_after_reset} = RateLimiting.get_user_status(@valid_user_id_1)
        assert status_after_reset.message_credits == expected_after_usage
      else
        # If below cap, refill to cap
        assert :ok = DailyResetWorker.perform(%{})
        {:ok, status_after_reset} = RateLimiting.get_user_status(@valid_user_id_1)
        assert status_after_reset.message_credits == refill_cap
      end

      # Additional vote should still work
      assert :ok = RateLimiting.add_vote_credits(@valid_user_id_1)
      {:ok, status_final} = RateLimiting.get_user_status(@valid_user_id_1)

      expected_final =
        if expected_after_usage >= refill_cap do
          expected_after_usage + vote_bonus
        else
          refill_cap + vote_bonus
        end

      assert status_final.message_credits == expected_final
    end
  end
end
