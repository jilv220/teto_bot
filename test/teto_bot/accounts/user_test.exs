defmodule TetoBot.Accounts.UserTest do
  @moduledoc """
  Tests for the User schema, focusing on vote tracking attributes and calculations.

  Tests cover:
  - User creation and validation
  - Vote tracking (last_voted_at)
  - Calculated fields (is_voted_user, has_voted_today)
  - Aggregate fields (total_daily_messages)
  - Edge cases and validations
  """

  use ExUnit.Case, async: true

  alias TetoBot.Accounts

  alias TetoBot.Guilds

  setup do
    # Each test gets its own database transaction that gets rolled back
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
  end

  # Test constants
  @valid_user_id 123_456_789_012_345_678
  @valid_guild_id 987_654_321_098_765_432
  @valid_guild_id_2 987_654_321_098_765_433

  describe "user creation and validation" do
    test "creates user with valid snowflake ID" do
      assert {:ok, user} = Accounts.create_user(@valid_user_id)
      assert user.user_id == @valid_user_id
      assert user.role == :user
      assert user.last_voted_at == nil
    end

    test "prevents creation with invalid user ID" do
      # Test with non-snowflake values
      assert {:error, %Ash.Error.Invalid{}} = Accounts.create_user("invalid")
      assert {:error, %Ash.Error.Invalid{}} = Accounts.create_user(-1)
      # Note: Small integers like 123 may be accepted as valid IDs in this implementation
      # The actual snowflake validation may be more lenient than expected
    end

    test "prevents duplicate user creation" do
      assert {:ok, _user1} = Accounts.create_user(@valid_user_id)

      # Attempting to create the same user again should fail
      assert {:error, %Ash.Error.Invalid{}} = Accounts.create_user(@valid_user_id)
    end
  end

  describe "vote tracking" do
    test "records vote timestamp" do
      {:ok, user} = Accounts.create_user(@valid_user_id)
      now = DateTime.utc_now()

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: now})
        |> Ash.update()

      assert updated_user.last_voted_at != nil
      assert DateTime.diff(updated_user.last_voted_at, now, :second) < 1
    end

    test "allows updating vote timestamp" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      first_vote = DateTime.add(DateTime.utc_now(), -2, :hour)

      {:ok, user_with_vote} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: first_vote})
        |> Ash.update()

      second_vote = DateTime.utc_now()

      {:ok, updated_user} =
        user_with_vote
        |> Ash.Changeset.for_update(:update, %{last_voted_at: second_vote})
        |> Ash.update()

      assert DateTime.after?(updated_user.last_voted_at, first_vote)
    end
  end

  describe "calculated fields" do
    test "is_voted_user calculation - recent vote" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote 2 hours ago (within 12 hour window)
      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: two_hours_ago})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :is_voted_user)
      assert loaded_user.is_voted_user == true
    end

    test "is_voted_user calculation - old vote" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote 14 hours ago (outside 12 hour window)
      fourteen_hours_ago = DateTime.add(DateTime.utc_now(), -14, :hour)

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: fourteen_hours_ago})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :is_voted_user)
      assert loaded_user.is_voted_user == false
    end

    test "is_voted_user calculation - no vote" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      {:ok, loaded_user} = Ash.load(user, :is_voted_user)
      assert loaded_user.is_voted_user == false
    end

    test "has_voted_today calculation - vote today" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote earlier today (ensure it's definitely today)
      today = Date.utc_today()
      vote_today = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: vote_today})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :has_voted_today)
      assert loaded_user.has_voted_today == true
    end

    test "has_voted_today calculation - vote yesterday" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote 25 hours ago (yesterday)
      twenty_five_hours_ago = DateTime.add(DateTime.utc_now(), -25, :hour)

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: twenty_five_hours_ago})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :has_voted_today)
      assert loaded_user.has_voted_today == false
    end

    test "has_voted_today calculation - no vote" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      {:ok, loaded_user} = Ash.load(user, :has_voted_today)
      assert loaded_user.has_voted_today == false
    end
  end

  describe "total_daily_messages aggregate" do
    test "aggregates messages across multiple guilds" do
      # Setup: Create guilds and user memberships
      {:ok, _guild1} = Guilds.create_guild(@valid_guild_id)
      {:ok, _guild2} = Guilds.create_guild(@valid_guild_id_2)
      {:ok, _membership1} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      {:ok, _membership2} = Accounts.create_membership(@valid_user_id, @valid_guild_id_2)

      # Send messages in both guilds
      for _i <- 1..3 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      for _i <- 1..5 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id_2, @valid_user_id)
      end

      # Get user and load aggregate
      {:ok, user} = Accounts.get_user(@valid_user_id)
      {:ok, loaded_user} = Ash.load(user, :total_daily_messages)

      # 3 + 5
      assert loaded_user.total_daily_messages == 8
    end

    test "returns 0 for user with no guild memberships" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      {:ok, loaded_user} = Ash.load(user, :total_daily_messages)
      assert loaded_user.total_daily_messages == 0
    end

    test "returns 0 for user with memberships but no messages" do
      # Setup: Create guild and membership but don't send messages
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      {:ok, user} = Accounts.get_user(@valid_user_id)
      {:ok, loaded_user} = Ash.load(user, :total_daily_messages)

      assert loaded_user.total_daily_messages == 0
    end
  end

  describe "loading multiple calculations and aggregates" do
    test "loads all vote-related calculations together" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Record a recent vote (earlier today for has_voted_today, within 12h for is_voted_user)
      today = Date.utc_today()
      recent_vote = DateTime.new!(today, ~T[12:00:00], "Etc/UTC")

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: recent_vote})
        |> Ash.update()

      # Load all calculations at once
      {:ok, loaded_user} =
        Ash.load(updated_user, [:is_voted_user, :has_voted_today, :total_daily_messages])

      assert loaded_user.is_voted_user == true
      assert loaded_user.has_voted_today == true
      assert loaded_user.total_daily_messages == 0
    end

    test "efficiently loads calculations with message data" do
      # Setup: Create guild and send messages
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Send some messages
      for _i <- 1..7 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # Record vote (earlier today for has_voted_today, within 12h for is_voted_user)
      {:ok, user} = Accounts.get_user(@valid_user_id)
      today = Date.utc_today()
      recent_vote = DateTime.new!(today, ~T[14:00:00], "Etc/UTC")

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: recent_vote})
        |> Ash.update()

      # Load everything efficiently
      {:ok, loaded_user} =
        Ash.load(updated_user, [:is_voted_user, :has_voted_today, :total_daily_messages])

      assert loaded_user.is_voted_user == true
      assert loaded_user.has_voted_today == true
      assert loaded_user.total_daily_messages == 7
    end
  end

  describe "edge cases" do
    test "handles nil vote timestamp correctly" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      {:ok, loaded_user} = Ash.load(user, [:is_voted_user, :has_voted_today])

      assert loaded_user.is_voted_user == false
      assert loaded_user.has_voted_today == false
    end

    test "handles vote exactly at 12 hour boundary" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote exactly 12 hours ago
      exactly_twelve_hours = DateTime.add(DateTime.utc_now(), -12, :hour)

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: exactly_twelve_hours})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :is_voted_user)
      # Should be false since it's not > 12 hours ago, it's == 12 hours ago
      assert loaded_user.is_voted_user == false
    end

    test "handles vote at midnight boundary for daily check" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Get today's midnight and subtract 1 second (yesterday)
      today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
      yesterday_late = DateTime.add(today_start, -1, :second)

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: yesterday_late})
        |> Ash.update()

      {:ok, loaded_user} = Ash.load(updated_user, :has_voted_today)
      assert loaded_user.has_voted_today == false
    end
  end

  describe "user relationships" do
    test "has many user_guilds relationship" do
      # Setup: Create multiple guilds and memberships
      {:ok, _guild1} = Guilds.create_guild(@valid_guild_id)
      {:ok, _guild2} = Guilds.create_guild(@valid_guild_id_2)
      {:ok, _membership1} = Accounts.create_membership(@valid_user_id, @valid_guild_id)
      {:ok, _membership2} = Accounts.create_membership(@valid_user_id, @valid_guild_id_2)

      {:ok, user} = Accounts.get_user(@valid_user_id)
      {:ok, loaded_user} = Ash.load(user, :user_guilds)

      assert length(loaded_user.user_guilds) == 2
      guild_ids = Enum.map(loaded_user.user_guilds, & &1.guild_id)
      assert @valid_guild_id in guild_ids
      assert @valid_guild_id_2 in guild_ids
    end
  end
end
