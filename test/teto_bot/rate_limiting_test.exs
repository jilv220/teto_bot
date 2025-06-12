defmodule TetoBot.RateLimitingTest do
  @moduledoc """
  Tests for the RateLimiting context, verifying both channel and user rate limiting functionality.

  Tests cover:
  - Channel rate limiting (time-based windows)
  - User rate limiting (daily message limits)
  - Free user limits (10 messages/day)
  - Voted user limits (30 messages/day)
  - Vote recording and benefits
  - Cross-guild message counting
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

  describe "allow_user?/1 - user rate limiting logic" do
    test "allows messages for new users under free limit" do
      # New user should start with 0 messages and be allowed
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
    end

    test "blocks messages when free user reaches daily limit" do
      # Setup: Create guild and user with maximum free messages (10)
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Simulate 10 messages (free limit)
      for _i <- 1..10 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # 11th message should be blocked
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end

    test "allows more messages for voted users" do
      # Setup: Create guild and user
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Record a vote (grants 30 messages/day)
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Simulate 25 messages (would exceed free limit but under voted limit)
      for _i <- 1..25 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # Should still be allowed (25 < 30)
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)
    end

    test "blocks voted users at their daily limit" do
      # Setup: Create guild and user
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Record a vote (grants 30 messages/day)
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Simulate 30 messages (voted user limit)
      for _i <- 1..30 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # 31st message should be blocked
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end

    test "counts messages across multiple guilds" do
      # Setup: Create two guilds and user memberships
      {:ok, _guild1} = Guilds.create_guild(@valid_guild_id)
      {:ok, _guild2} = Guilds.create_guild(@valid_guild_id_2)
      {:ok, _membership1} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      {:ok, _membership2} = Accounts.create_membership(@valid_user_id, @valid_guild_id_2)

      # Send 5 messages in each guild (10 total - at free limit)
      for _i <- 1..5 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id_2, @valid_user_id)
      end

      # Should be blocked (10 messages total = free limit)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(nil)
      assert {:error, :invalid_user_id} = RateLimiting.allow_user?(-1)
    end
  end

  describe "record_vote/1 - vote tracking" do
    test "successfully records a vote for valid user" do
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Verify user was created and vote was recorded
      {:ok, user} = Accounts.get_user(@valid_user_id)
      assert user.last_voted_at != nil
    end

    test "updates vote timestamp for existing user" do
      # Create user first
      {:ok, _user} = Accounts.create_user(@valid_user_id)

      # Record initial vote with specific timestamp
      first_vote_time = DateTime.add(DateTime.utc_now(), -1, :hour)
      {:ok, user} = Accounts.get_user(@valid_user_id)

      {:ok, _user_with_vote} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: first_vote_time})
        |> Ash.update()

      # Record another vote (should update to current time)
      assert :ok = RateLimiting.record_vote(@valid_user_id)
      {:ok, user2} = Accounts.get_user(@valid_user_id)
      updated_vote_time = user2.last_voted_at

      # Vote time should be updated to be more recent
      assert DateTime.after?(updated_vote_time, first_vote_time)
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
               daily_limit: 10,
               current_count: 0,
               remaining: 10,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "returns correct status for user with messages" do
      # Setup: Create guild and send some messages
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Send 3 messages
      for _i <- 1..3 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               daily_limit: 10,
               current_count: 3,
               remaining: 7,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "returns correct status for voted user" do
      # Setup: Create guild and record vote
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      assert :ok = RateLimiting.record_vote(@valid_user_id)

      # Send 5 messages
      for _i <- 1..5 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               daily_limit: 30,
               current_count: 5,
               remaining: 25,
               has_voted_today: true,
               is_voted_user: true
             } = status
    end

    test "aggregates messages across multiple guilds in status" do
      # Setup: Create two guilds
      {:ok, _guild1} = Guilds.create_guild(@valid_guild_id)
      {:ok, _guild2} = Guilds.create_guild(@valid_guild_id_2)
      {:ok, _membership1} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      {:ok, _membership2} = Accounts.create_membership(@valid_user_id, @valid_guild_id_2)

      # Send messages in both guilds
      for _i <- 1..3 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      for _i <- 1..4 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id_2, @valid_user_id)
      end

      assert {:ok, status} = RateLimiting.get_user_status(@valid_user_id)

      assert %{
               daily_limit: 10,
               # 3 + 4
               current_count: 7,
               # 10 - 7
               remaining: 3,
               has_voted_today: false,
               is_voted_user: false
             } = status
    end

    test "rejects invalid user IDs" do
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status("invalid")
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(nil)
      assert {:error, :invalid_user_id} = RateLimiting.get_user_status(-1)
    end
  end

  describe "get_user_config/0 - configuration access" do
    test "returns current configuration" do
      config = RateLimiting.get_user_config()

      assert %{
               free_user_daily_limit: 10,
               voted_user_daily_limit: 30
             } = config
    end
  end

  describe "combined rate limiting behavior" do
    test "both channel and user limits must allow for message processing" do
      # Setup: Create guild for user testing
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Both should initially allow
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, true} = RateLimiting.allow_user?(@valid_user_id)

      # If user reaches limit, channel being allowed shouldn't matter
      for _i <- 1..10 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # Channel still allows but user doesn't
      assert true = RateLimiting.allow_channel?(@valid_channel_id)
      assert {:ok, false} = RateLimiting.allow_user?(@valid_user_id)
    end
  end
end
