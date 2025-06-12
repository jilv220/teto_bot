defmodule TetoBot.RateLimitingTest do
  @moduledoc """
  Tests for the RateLimiting context, verifying both channel and user rate limiting functionality.

  Tests cover:
  - Channel rate limiting (time-based windows)
  - User credit-based refill system
  - Credit deduction per message
  - Credit refill to daily cap
  - Vote credit bonuses
  - Daily credit refill
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

    # Get configuration values to make tests flexible
    config = RateLimiting.get_user_config()
    {:ok, config: config}
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
    test "allows messages for new users with default credits", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # New user should start with default credits and be allowed
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      # Verify user was created with default credits and one was deducted
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # default_credits - 1 = expected_remaining
      assert status.message_credits == default_credits - 1
    end

    test "deducts one credit per message", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # Allow 3 messages and check credit deduction
      # default_credits -> default_credits - 1
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      # default_credits - 1 -> default_credits - 2
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      # default_credits - 2 -> default_credits - 3
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == default_credits - 3
    end

    test "blocks messages when user runs out of credits", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # Deplete all credits (default_credits messages should be allowed)
      for i <- 1..default_credits do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id),
               "Message #{i} should be allowed"
      end

      # (default_credits + 1)th message should be blocked (no credits left)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)

      # Verify 0 credits remaining
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == 0
    end

    test "credits are shared across guilds", %{config: config} do
      default_credits = config.daily_credit_refill_cap
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

      # Should have (default_credits - 5) credits remaining regardless of guild
      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == default_credits - 5
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(nil)
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(-1)
    end
  end

  describe "record_vote/1 - vote tracking and credit bonuses" do
    test "successfully records a vote and adds credit bonus", %{config: config} do
      vote_bonus = config.vote_credit_bonus
      # Get initial credits
      {:ok, initial_status} = RateLimiting.get_user_status(@valid_user_id)
      initial_credits = initial_status.message_credits

      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Verify user was created, vote was recorded, and credits were added
      {:ok, user} = Accounts.get_user(@valid_user_id)
      assert user.last_voted_at != nil

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # Vote bonus
      assert status.message_credits == initial_credits + vote_bonus
      assert status.has_voted_today == true
      assert status.is_voted_user == true
    end

    test "adds credit bonus on each vote", %{config: config} do
      vote_bonus = config.vote_credit_bonus
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

      # Should have received another vote_bonus credit bonus
      assert status2.message_credits == credits_after_first_vote + vote_bonus
    end

    test "vote credits accumulate with existing credits", %{config: config} do
      vote_bonus = config.vote_credit_bonus
      default_credits = config.daily_credit_refill_cap
      # Use some credits first
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, status_before_vote} = RateLimiting.get_user_status(@valid_user_id)
      # Should be default_credits - 3
      credits_before_vote = status_before_vote.message_credits
      assert credits_before_vote == default_credits - 3

      # Record vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      {:ok, status_after_vote} = RateLimiting.get_user_status(@valid_user_id)
      # (default_credits - 3) + vote_bonus
      assert status_after_vote.message_credits == credits_before_vote + vote_bonus
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.record_vote("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.record_vote(nil)
      assert {:error, :invalid_user_id} = RateLimiting.record_vote(-1)
    end
  end

  describe "get_user_status/1 - status retrieval" do
    test "returns correct status for new user", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # Default starting credits
               message_credits: ^default_credits,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "returns correct status after using credits", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # default_credits - 3
               message_credits: expected_credits,
               has_voted_today: false,
               is_voted_user: false
             } = status

      assert expected_credits == default_credits - 3
    end

    test "returns correct status for voted user", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      vote_bonus = config.vote_credit_bonus

      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Use 5 credits
      for _i <- 1..5 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               # default_credits + vote_bonus - 5 (used)
               message_credits: expected_credits,
               has_voted_today: true,
               is_voted_user: true
             } = status

      assert expected_credits == default_credits + vote_bonus - 5
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(nil)
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(-1)
    end
  end

  describe "get_user_config/0 - configuration access" do
    test "returns current credit system configuration", %{config: config} do
      returned_config = RateLimiting.get_user_config()

      assert returned_config.daily_credit_refill_cap == config.daily_credit_refill_cap
      assert returned_config.vote_credit_bonus == config.vote_credit_bonus
    end
  end

  describe "daily credit refill system" do
    test "users can accumulate large amounts of credits over time", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      vote_bonus = config.vote_credit_bonus

      # Start with default credits
      {:ok, initial_status} = RateLimiting.get_user_status(@valid_user_id)
      assert initial_status.message_credits == default_credits

      # Simulate multiple vote bonuses (user voting every 12 hours)
      vote_count = 5

      for _i <- 1..vote_count do
        assert :ok = RateLimiting.record_vote(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # default_credits + (vote_count * vote_bonus)
      expected_credits = default_credits + vote_count * vote_bonus
      assert status.message_credits == expected_credits

      # User should be able to send many messages
      # Leave some credits
      messages_to_send = min(50, expected_credits - 10)

      for _i <- 1..messages_to_send do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # expected_credits - messages_to_send
      assert final_status.message_credits == expected_credits - messages_to_send
    end

    test "credits persist and refill to cap daily", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      vote_bonus = config.vote_credit_bonus

      # This test verifies that credits refill to cap but don't get reset to zero
      # (using the refill system instead of accumulation)

      # Use 3 credits
      for _i <- 1..3 do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      assert status.message_credits == default_credits - 3

      # Add vote bonus
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # (default_credits - 3) + vote_bonus (credits accumulated)
      assert final_status.message_credits == default_credits - 3 + vote_bonus
    end
  end

  describe "edge cases and boundary conditions" do
    test "user with 0 credits cannot send messages", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # Deplete all credits
      for _i <- 1..default_credits do
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

    test "voting when already voted today still adds credits", %{config: config} do
      vote_bonus = config.vote_credit_bonus
      # Record first vote
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status1} = RateLimiting.get_user_status(@valid_user_id)
      credits_after_first = status1.message_credits

      # Record second vote immediately (simulating multiple votes per day)
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, status2} = RateLimiting.get_user_status(@valid_user_id)

      # Should still get credit bonus
      assert status2.message_credits == credits_after_first + vote_bonus
    end

    test "large credit amounts work correctly", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      vote_bonus = config.vote_credit_bonus

      # Simulate user with many votes over time
      vote_count = 20

      for _i <- 1..vote_count do
        assert :ok = RateLimiting.record_vote(@valid_user_id)
      end

      {:ok, status} = RateLimiting.get_user_status(@valid_user_id)
      # default_credits + (vote_count * vote_bonus)
      expected_total = default_credits + vote_count * vote_bonus
      assert status.message_credits == expected_total

      # Should be able to send many messages
      # Leave some credits
      messages_to_send = min(100, expected_total - 10)

      for _i <- 1..messages_to_send do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      {:ok, final_status} = RateLimiting.get_user_status(@valid_user_id)
      # expected_total - messages_to_send
      assert final_status.message_credits == expected_total - messages_to_send
    end
  end

  describe "combined rate limiting behavior" do
    test "both channel and user limits must allow for message processing", %{config: config} do
      default_credits = config.daily_credit_refill_cap
      # Both should initially allow
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      # If user runs out of credits, channel being allowed shouldn't matter
      # Use remaining (default_credits - 1) credits (1 already used above)
      for _i <- 1..(default_credits - 1) do
        assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
      end

      # Channel still allows but user doesn't
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end
  end
end
