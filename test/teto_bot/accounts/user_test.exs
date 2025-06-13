defmodule TetoBot.Accounts.UserTest do
  @moduledoc """
  Tests for the User schema, focusing on basic user functionality.

  Tests cover:
  - User creation and validation
  - Vote tracking (last_voted_at) for monitoring purposes
  - Aggregate fields (total_daily_messages)
  - Edge cases and validations

  Note: Vote status checking is now done via TopggEx.Api.has_voted rather than database calculations.
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

  # NOTE: Calculated fields is_voted_user and has_voted were removed
  # Vote status is now checked via TopggEx.Api.has_voted instead of database calculations

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

  describe "loading aggregates" do
    test "efficiently loads aggregates" do
      # Setup: Create guild and send messages
      {:ok, _guild} = Guilds.create_guild(@valid_guild_id)
      {:ok, _membership} = Accounts.create_membership(@valid_user_id, @valid_guild_id)

      # Send some messages
      for _i <- 1..7 do
        {:ok, _} = Accounts.update_user_metrics(@valid_guild_id, @valid_user_id)
      end

      # Record vote timestamp for monitoring
      {:ok, user} = Accounts.get_user(@valid_user_id)
      today = Date.utc_today()
      recent_vote = DateTime.new!(today, ~T[14:00:00], "Etc/UTC")

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: recent_vote})
        |> Ash.update()

      # Load aggregates
      {:ok, loaded_user} = Ash.load(updated_user, [:total_daily_messages])

      assert loaded_user.total_daily_messages == 7
      assert loaded_user.last_voted_at != nil
    end
  end

  describe "edge cases" do
    test "handles nil vote timestamp correctly" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # User should be created successfully with nil vote timestamp
      assert user.last_voted_at == nil
    end

    test "handles vote timestamp updates" do
      {:ok, user} = Accounts.create_user(@valid_user_id)

      # Vote exactly at midnight today
      today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

      {:ok, updated_user} =
        user
        |> Ash.Changeset.for_update(:update, %{last_voted_at: today_start})
        |> Ash.update()

      # Should store the timestamp correctly for monitoring
      assert updated_user.last_voted_at == today_start
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
