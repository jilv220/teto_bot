defmodule TetoBot.RateLimitingTest do
  @moduledoc """
  Tests for the RateLimiting context, verifying both channel and user rate limiting functionality.

  Tests cover:
  - Channel rate limiting (time-based windows)
  - User credit-based charging system
  - Credit deduction per message
  - Credit accumulation over time
  - Vote credit bonuses
  - Daily credit recharge
  - Cross-guild credit sharing
  - Edge cases and error handling
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TetoBot.RateLimiting
  alias TetoBot.Accounts
  alias TetoBot.Guilds

  setup do
    # Each test gets its own database transaction that gets rolled back
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
  end

  # Test constants
  @valid_user_id 123_456_789_012_345_678
  @valid_channel_id 123_456_789_012_345_679
  @valid_guild_id 987_654_321_098_765_432
  @valid_guild_id_2 987_654_321_098_765_433

  describe "allow_channel?/1 - channel rate limiting" do
    test "allows requests from new channels" do
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
    end

    test "rejects invalid channel IDs" do
      refute RateLimiting.allow_channel?("invalid")
      refute RateLimiting.allow_channel?(nil)
      refute RateLimiting.allow_channel?(-1)
    end
  end

  describe "allow_user?/1 - credit-based rate limiting" do
    test "allows messages for new users with default credits" do
      # New user should start with 10 credits and be allowed
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      # Verify user was created with default credits and one was deducted
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # 10 - 1 = 9
      assert status.message_credits == 9
    end

    test "deducts one credit per message" do
      # Allow 3 messages and check credit deduction
      # 10 -> 9
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      # 9 -> 8
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      # 8 -> 7
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 7
    end

    test "blocks messages when user runs out of credits" do
      # Deplete all credits (10 messages should be allowed)
      for i <- 1..10 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id),
               "Message #{i} should be allowed"
      end

      # 11th message should be blocked (no credits left)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)

      # Verify 0 credits remaining
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 0
    end

    test "credits are shared across guilds" do
      # Credits are user-level, not per-guild
      # Setup guilds for consistency but credits should be shared
      {:ok, _guild1} = Guilds.create_guild(@valid_guild_id)
      {:ok, _guild2} = Guilds.create_guild(@valid_guild_id_2)
      {:ok, _membership1} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      {:ok, _membership2} = Accounts.create_membership(@valid_user_id, @valid_guild_id_2)

      # Use 5 credits
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      # Should have 5 credits remaining regardless of guild
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 5
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(nil)
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(-1)
    end
  end

  describe "record_vote/1 - vote tracking and credit bonuses" do
    test "successfully records a vote and adds credit bonus" do
      # Get initial credits
      {:ok, initial_status} = RateLimiting.get_user_status(@valid_user_id)
      initial_credits = initial_status.message_credits

      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Verify user was created, vote was recorded, and credits were added
      {:ok, user} = Accounts.get_user(@valid_user_id)
      assert user.last_voted_at != nil

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # Vote bonus
      assert status.message_credits == initial_credits + 10
      assert status.has_voted_today == true
      assert status.is_voted_user == true
    end

    test "adds credit bonus on each vote" do
      # Record first vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status1} = RateLimiting.get_user_status(@valid_user_id)
      credits_after_first_vote = status1.message_credits

      # Update vote timestamp to simulate another vote (in real scenario this would be 12 hours later)
      {:ok, user} = Accounts.get_user(@valid_user_id)
      past_time = DateTime.add(DateTime.utc_now(), -13, :hour)

      {:ok, _} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: past_time})
        |> Ash.update()

      # Record second vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status2} = RateLimiting.get_user_status(@valid_user_id)

      # Should have received another 10 credit bonus
      assert status2.message_credits == credits_after_first_vote + 10
    end

    test "vote credits accumulate with existing credits" do
      # Use some credits first
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, status_before_vote} = RateLimiting.get_user_status(@valid_user_id)
      # Should be 7
      credits_before_vote = status_before_vote.message_credits

      # Record vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      {:ok, status_after_vote} = RateLimiting.get_user_status(@valid_user_id)
      # 7 + 10 = 17
      assert status_after_vote.message_credits == credits_before_vote + 10
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.record_vote("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.record_vote(nil)
      assert {:error, :invalid_user_id} = RateLimiting.record_vote(-1)
    end
  end

  describe "get_user_status/1 - status retrieval" do
    test "returns correct status for new user" do
      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # Default starting credits
               message_credits: 10,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "returns correct status after using credits" do
      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # 10 - 3 = 7
               message_credits: 7,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "returns correct status for voted user" do
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Use 5 credits
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # 10 + 10 (vote) - 5 (used) = 15
               message_credits: 15,
               has_voted_today: true,
               is_voted_user: true
             } = status
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(nil)
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(-1)
    end
  end

  describe "get_user_config/0 - configuration access" do
    test "returns current credit system configuration" do
      config = RateLimiting.get_user_config()

      assert %{
               daily_credit_recharge: 10,
               vote_credit_bonus: 10
             } = config
    end
  end

  describe "daily credit recharge system" do
    test "users can accumulate large amounts of credits over time" do
      # Start with default credits
      {:ok, initial_status} = RateLimiting.get_user_status(@valid_user_id)
      assert initial_status.message_credits == 10

      # Simulate multiple vote bonuses (user voting every 12 hours)
      for _i <- 1..5 do
        assert :ok = RateLimiting.record_vote(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # 10 + (5 * 10) = 60 credits
      assert status.message_credits == 60

      # User should be able to send many messages
      for _i <- 1..50 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # 60 - 50 = 10
      assert final_status.message_credits == 10
    end

    test "credits persist and don't reset daily" do
      # This test verifies that credits accumulate and don't get reset
      # (unlike the old daily limit system)

      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 7

      # Add vote bonus
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # 7 + 10 = 17 (credits accumulated)
      assert final_status.message_credits == 17
    end
  end

  describe "edge cases and boundary conditions" do
    test "user with 0 credits cannot send messages" do
      # Deplete all credits
      for _i <- 1..10 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      # Verify 0 credits and blocked
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 0
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)

      # Credits should still be 0 (no deduction when blocked)
      {:ok, status2} = RateLimiting.get_user_status(@valid_user_id)
      assert status2.message_credits == 0
    end

    test "voting when already voted today still adds credits" do
      # Record first vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status1} = RateLimiting.get_user_status(@valid_user_id)
      credits_after_first = status1.message_credits

      # Record second vote immediately (simulating multiple votes per day)
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status2} = RateLimiting.get_user_status(@valid_user_id)

      # Should still get credit bonus
      assert status2.message_credits == credits_after_first + 10
    end

    test "large credit amounts work correctly" do
      # Simulate user with many votes over time
      for _i <- 1..20 do
        assert :ok = RateLimiting.record_vote(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # 10 + (20 * 10) = 210
      assert status.message_credits == 210

      # Should be able to send many messages
      for _i <- 1..100 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # 210 - 100 = 110
      assert final_status.message_credits == 110
    end
  end

  describe "combined rate limiting behavior" do
    test "both channel and user limits must allow for message processing" do
      # Both should initially allow
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      # If user runs out of credits, channel being allowed shouldn't matter
      # Use remaining 9 credits (1 already used above)
      for _i <- 1..9 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      # Channel still allows but user doesn't
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end
  end
end
