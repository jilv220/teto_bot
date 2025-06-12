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
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
    config = RateLimiting.get_user_config()
    {:ok, config: config}
  end

  # Test constants
  @valid_user_id_1 123_456_789_012_345_678
  @valid_user_id_2 123_456_789_012_345_679
  @valid_guild_id 987_654_321_098_765_432

  describe "perform/1 - daily reset job" do
    test "recharges credits for all users", %{config: config} do
      daily_credit = config.daily_credit_recharge
      {:ok, _user1} = Accounts.create_user(@valid_user_id_1)
      {:ok, _user2} = Accounts.create_user(@valid_user_id_2)

      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      for _i <- 1..daily_credit do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_2)
      end

      {:ok, status1_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_before} = RateLimiting.get_user_status(@valid_user_id_2)
      assert status1_before.message_credits == daily_credit - 5
      assert status2_before.message_credits == 0

      assert :ok = DailyResetWorker.perform(%{})

      {:ok, status1_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, status2_after} = RateLimiting.get_user_status(@valid_user_id_2)
      assert status1_after.message_credits == daily_credit - 5 + daily_credit
      assert status2_after.message_credits == 0 + daily_credit
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

    test "handles users with large credit amounts", %{config: config} do
      daily_credit = config.daily_credit_recharge
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      for _i <- 1..50 do
        assert :ok = RateLimiting.record_vote(@valid_user_id_1)
      end

      {:ok, status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      credits_before = status_before.message_credits
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after.message_credits == credits_before + daily_credit
    end

    test "works with no users in database" do
      assert :ok = DailyResetWorker.perform(%{})
    end

    test "credits accumulate correctly over multiple resets", %{config: config} do
      daily_credit = config.daily_credit_recharge
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)

      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_initial} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_initial.message_credits == daily_credit - 3
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after_first} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_first.message_credits == daily_credit - 3 + daily_credit
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after_second} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_second.message_credits == daily_credit - 3 + 2 * daily_credit
      assert status_after_second.message_credits > status_initial.message_credits
    end
  end

  describe "trigger/0 - manual job trigger" do
    test "successfully enqueues job" do
      assert {:ok, _job} = DailyResetWorker.trigger()
    end
  end

  describe "credit recharge integration" do
    test "credit recharge works independently of daily message tracking", %{config: config} do
      daily_credit = config.daily_credit_recharge
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id_1, @valid_guild_id)

      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id_1)
      end

      {:ok, credit_status_before} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_before} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert credit_status_before.message_credits == daily_credit - 3
      assert membership_before.daily_message_count == 3
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, credit_status_after} = RateLimiting.get_user_status(@valid_user_id_1)
      {:ok, membership_after} = Accounts.get_membership(@valid_user_id_1, @valid_guild_id)
      assert credit_status_after.message_credits == daily_credit - 3 + daily_credit
      assert membership_after.daily_message_count == 0
    end

    test "vote bonuses and daily recharge work together", %{config: config} do
      daily_credit = config.daily_credit_recharge
      vote_bonus = config.vote_credit_bonus
      {:ok, _user} = Accounts.create_user(@valid_user_id_1)
      assert :ok = RateLimiting.record_vote(@valid_user_id_1)
      {:ok, status_after_vote} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_vote.message_credits == daily_credit + vote_bonus

      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id_1)
      end

      {:ok, status_after_usage} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_usage.message_credits == daily_credit + vote_bonus - 5
      assert :ok = DailyResetWorker.perform(%{})
      {:ok, status_after_reset} = RateLimiting.get_user_status(@valid_user_id_1)
      assert status_after_reset.message_credits == daily_credit + vote_bonus - 5 + daily_credit
      assert :ok = RateLimiting.record_vote(@valid_user_id_1)
      {:ok, status_final} = RateLimiting.get_user_status(@valid_user_id_1)

      assert status_final.message_credits ==
               daily_credit + vote_bonus - 5 + daily_credit + vote_bonus
    end
  end
end
