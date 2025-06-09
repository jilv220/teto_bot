defmodule TetoBot.Accounts.ForeignKeyConstraintTest do
  @moduledoc """
  Tests focused on preventing foreign key constraint violations when creating user_guild records.
  This ensures the bug from guild join scenario doesn't regress.

  Uses Ash's built-in test isolation - no manual cleanup needed!
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TetoBot.Accounts

  setup do
    # Each test gets its own database transaction that gets rolled back
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TetoBot.Repo)
  end

  # Use the exact IDs from the original error
  @problematic_user_id 394_594_679_221_518_336
  @problematic_guild_id 333_949_691_962_195_969

  describe "property-based tests" do
    test "create_membership works with random valid snowflakes" do
      # Generate random valid snowflakes
      check all(
              {user_id, guild_id} <- {
                integer(100_000_000_000_000_000..900_000_000_000_000_000),
                integer(100_000_000_000_000_000..900_000_000_000_000_000)
              }
            ) do
        assert {:ok, membership} = Accounts.create_membership(user_id, guild_id)
        assert membership.user_id == user_id
        assert membership.guild_id == guild_id
      end
    end

    property "create_membership works with any valid snowflake range" do
      check all(
              {user_id, guild_id} <- {
                integer(100_000_000_000_000_000..900_000_000_000_000_000),
                integer(100_000_000_000_000_000..900_000_000_000_000_000)
              }
            ) do
        # This should work without foreign key constraint violations
        assert {:ok, membership} = Accounts.create_membership(user_id, guild_id)
        assert membership.user_id == user_id
        assert membership.guild_id == guild_id
      end
    end
  end

  describe "Foreign key constraint regression tests" do
    test "create_membership creates user automatically when user doesn't exist" do
      # Use a specific test ID to ensure predictable behavior
      unique_user_id = @problematic_user_id + 100

      # Verify user doesn't exist initially
      assert {:ok, nil} = Accounts.get_user(unique_user_id)

      # create_membership should create user first, then membership
      assert {:ok, membership} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      # Verify both user and membership were created
      assert {:ok, user} = Accounts.get_user(unique_user_id)
      assert user.user_id == unique_user_id

      assert membership.user_id == unique_user_id
      assert membership.guild_id == @problematic_guild_id
      assert membership.intimacy == 0
    end

    test "update_user_metrics creates user automatically when user doesn't exist" do
      # Use a valid snowflake in PostgreSQL bigint range
      unique_user_id = @problematic_user_id + 200

      # Verify user doesn't exist initially
      assert {:ok, nil} = Accounts.get_user(unique_user_id)

      # update_user_metrics should create user first, then membership
      assert {:ok, %{user_guild: membership}} =
               Accounts.update_user_metrics(@problematic_guild_id, unique_user_id)

      # Verify both user and membership were created
      assert {:ok, user} = Accounts.get_user(unique_user_id)
      assert user.user_id == unique_user_id

      assert membership.user_id == unique_user_id
      assert membership.guild_id == @problematic_guild_id
      assert membership.daily_message_count == 1
      # First message gives 1 intimacy
      assert membership.intimacy == 1
      assert membership.last_message_at != nil
    end

    test "feed_teto creates user automatically when user doesn't exist" do
      # Use a valid snowflake in PostgreSQL bigint range
      unique_user_id = @problematic_user_id + 300

      # Verify user doesn't exist initially
      assert {:ok, nil} = Accounts.get_user(unique_user_id)

      increment = 5
      # feed_teto should create user first, then membership
      assert {:ok, %{user_guild: membership}} =
               Accounts.feed_teto(@problematic_guild_id, unique_user_id, increment)

      # Verify both user and membership were created
      assert {:ok, user} = Accounts.get_user(unique_user_id)
      assert user.user_id == unique_user_id

      assert membership.user_id == unique_user_id
      assert membership.guild_id == @problematic_guild_id
      assert membership.intimacy == increment
      assert membership.last_feed != nil
    end

    test "multiple users can join simultaneously without race conditions" do
      # Use valid snowflakes in PostgreSQL bigint range
      user_id1 = @problematic_user_id + 400
      user_id2 = @problematic_user_id + 500
      user_id3 = @problematic_user_id + 600

      # All should be able to create memberships without issues
      assert {:ok, membership1} = Accounts.create_membership(user_id1, @problematic_guild_id)
      assert {:ok, membership2} = Accounts.create_membership(user_id2, @problematic_guild_id)
      assert {:ok, membership3} = Accounts.create_membership(user_id3, @problematic_guild_id)

      # Verify all memberships were created correctly
      assert membership1.user_id == user_id1
      assert membership2.user_id == user_id2
      assert membership3.user_id == user_id3

      # Verify all users were created
      assert {:ok, _} = Accounts.get_user(user_id1)
      assert {:ok, _} = Accounts.get_user(user_id2)
      assert {:ok, _} = Accounts.get_user(user_id3)
    end
  end

  describe "membership behavior tests" do
    test "create_membership works with existing user" do
      # Use a valid snowflake in PostgreSQL bigint range
      unique_user_id = @problematic_user_id + 700
      assert {:ok, _created_user} = Accounts.create_user(unique_user_id)

      # Create membership should work normally
      assert {:ok, membership} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      assert membership.user_id == unique_user_id
      assert membership.guild_id == @problematic_guild_id
    end

    test "create_membership with generated user_guild works" do
      # Use a valid snowflake in PostgreSQL bigint range
      unique_user_id = @problematic_user_id + 800

      # Create membership using the generated data
      assert {:ok, membership} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      assert membership.user_id == unique_user_id
    end
  end

  describe "Edge cases and error conditions" do
    test "create_membership fails gracefully with invalid IDs" do
      # Use negative values which are invalid snowflakes
      invalid_user_id = -1
      invalid_guild_id = -2

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_membership(invalid_user_id, @problematic_guild_id)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_membership(@problematic_user_id, invalid_guild_id)

      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_membership(invalid_user_id, invalid_guild_id)
    end

    test "duplicate membership creation fails appropriately" do
      # Use a valid snowflake in PostgreSQL bigint range (max 9223372036854775807)
      unique_user_id = @problematic_user_id + 999

      # Create first membership
      assert {:ok, _membership1} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      # Second creation should fail with unique constraint error
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)
    end
  end
end
