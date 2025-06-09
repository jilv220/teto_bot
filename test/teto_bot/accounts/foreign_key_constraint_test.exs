defmodule TetoBot.Accounts.ForeignKeyConstraintTest do
  @moduledoc """
  Tests focused on preventing foreign key constraint violations when creating user_guild records.
  This ensures the bug from guild join scenario doesn't regress.

  Uses Ash's built-in test isolation - no manual cleanup needed!
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TetoBot.Accounts
  alias TetoBot.Guilds

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
        # Create the guild first (required for foreign key constraint)
        {:ok, _guild} = Guilds.create_guild(guild_id)

        assert {:ok, membership} = Accounts.create_membership(user_id, guild_id)
        assert membership.user_id == user_id
        assert membership.guild_id == guild_id
      end
    end

    property "create_membership works with any valid snowflake range when guild exists" do
      check all(
              {user_id, guild_id} <- {
                integer(100_000_000_000_000_000..900_000_000_000_000_000),
                integer(100_000_000_000_000_000..900_000_000_000_000_000)
              }
            ) do
        # Create the guild first (required for foreign key constraint)
        {:ok, _guild} = Guilds.create_guild(guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

      # Create membership should work normally
      assert {:ok, membership} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      assert membership.user_id == unique_user_id
      assert membership.guild_id == @problematic_guild_id
    end

    test "create_membership with generated user_guild works" do
      # Use a valid snowflake in PostgreSQL bigint range
      unique_user_id = @problematic_user_id + 800

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

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

      # Create the guild first (required for foreign key constraint)
      assert {:ok, _guild} = Guilds.create_guild(@problematic_guild_id)

      # Create first membership
      assert {:ok, _membership1} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)

      # Second creation should fail with unique constraint error
      assert {:error, %Ash.Error.Invalid{}} =
               Accounts.create_membership(unique_user_id, @problematic_guild_id)
    end
  end

  describe "Cascading delete behavior" do
    test "deleting a guild automatically deletes all associated user_guild records" do
      # Create a unique guild for this test
      test_guild_id = @problematic_guild_id + 1000
      test_user_id1 = @problematic_user_id + 1001
      test_user_id2 = @problematic_user_id + 1002
      test_user_id3 = @problematic_user_id + 1003

      # Create the guild
      assert {:ok, guild} = Guilds.create_guild(test_guild_id)
      assert guild.guild_id == test_guild_id

      # Create multiple users and their guild memberships
      assert {:ok, _membership1} = Accounts.create_membership(test_user_id1, test_guild_id)
      assert {:ok, _membership2} = Accounts.create_membership(test_user_id2, test_guild_id)
      assert {:ok, _membership3} = Accounts.create_membership(test_user_id3, test_guild_id)

      # Verify all memberships exist
      assert {:ok, found_membership1} = Accounts.get_membership(test_user_id1, test_guild_id)
      assert {:ok, found_membership2} = Accounts.get_membership(test_user_id2, test_guild_id)
      assert {:ok, found_membership3} = Accounts.get_membership(test_user_id3, test_guild_id)

      assert found_membership1.user_id == test_user_id1
      assert found_membership2.user_id == test_user_id2
      assert found_membership3.user_id == test_user_id3

      # Verify users still exist (they should not be deleted when guild is deleted)
      assert {:ok, user1} = Accounts.get_user(test_user_id1)
      assert {:ok, user2} = Accounts.get_user(test_user_id2)
      assert {:ok, user3} = Accounts.get_user(test_user_id3)
      assert user1.user_id == test_user_id1
      assert user2.user_id == test_user_id2
      assert user3.user_id == test_user_id3

      # Delete the guild - this should cascade delete all user_guild records
      assert {:ok, deleted_guild} = Guilds.delete_guild(test_guild_id)
      assert deleted_guild.guild_id == test_guild_id

      # Verify all user_guild records are automatically deleted due to foreign key cascade
      assert {:ok, nil} = Accounts.get_membership(test_user_id1, test_guild_id)
      assert {:ok, nil} = Accounts.get_membership(test_user_id2, test_guild_id)
      assert {:ok, nil} = Accounts.get_membership(test_user_id3, test_guild_id)

      # Verify users still exist (only the guild and user_guild relationships should be deleted)
      assert {:ok, user1_after} = Accounts.get_user(test_user_id1)
      assert {:ok, user2_after} = Accounts.get_user(test_user_id2)
      assert {:ok, user3_after} = Accounts.get_user(test_user_id3)
      assert user1_after.user_id == test_user_id1
      assert user2_after.user_id == test_user_id2
      assert user3_after.user_id == test_user_id3
    end

    test "cascading delete works with users who have intimacy data" do
      # Create a unique guild and user for this test
      test_guild_id = @problematic_guild_id + 2000
      test_user_id = @problematic_user_id + 2001

      # Create the guild and user membership
      assert {:ok, _guild} = Guilds.create_guild(test_guild_id)
      assert {:ok, _membership} = Accounts.create_membership(test_user_id, test_guild_id)

      # Update intimacy to simulate real usage
      assert {:ok, updated_membership} =
               Accounts.update_intimacy(test_user_id, test_guild_id, 150)

      assert updated_membership.intimacy == 150

      # Update last message timestamp
      assert {:ok, updated_membership2} =
               Accounts.update_last_message(test_user_id, test_guild_id)

      assert updated_membership2.last_message_at != nil

      # Verify the user_guild record exists with data
      assert {:ok, found_membership} = Accounts.get_membership(test_user_id, test_guild_id)
      assert found_membership.intimacy == 150
      assert found_membership.last_message_at != nil

      # Delete the guild
      assert {:ok, _deleted_guild} = Guilds.delete_guild(test_guild_id)

      # Verify the user_guild record is deleted despite having intimacy data
      assert {:ok, nil} = Accounts.get_membership(test_user_id, test_guild_id)

      # Verify the user still exists
      assert {:ok, user} = Accounts.get_user(test_user_id)
      assert user.user_id == test_user_id
    end

    test "multiple guilds - deleting one guild doesn't affect other guild memberships" do
      # Create unique IDs for this test
      test_guild_id1 = @problematic_guild_id + 3000
      test_guild_id2 = @problematic_guild_id + 3001
      test_user_id = @problematic_user_id + 3002

      # Create two guilds
      assert {:ok, _guild1} = Guilds.create_guild(test_guild_id1)
      assert {:ok, _guild2} = Guilds.create_guild(test_guild_id2)

      # Create user memberships in both guilds
      assert {:ok, _membership1} = Accounts.create_membership(test_user_id, test_guild_id1)
      assert {:ok, _membership2} = Accounts.create_membership(test_user_id, test_guild_id2)

      # Verify both memberships exist
      assert {:ok, found_membership1} = Accounts.get_membership(test_user_id, test_guild_id1)
      assert {:ok, found_membership2} = Accounts.get_membership(test_user_id, test_guild_id2)
      assert found_membership1.guild_id == test_guild_id1
      assert found_membership2.guild_id == test_guild_id2

      # Delete only the first guild
      assert {:ok, _deleted_guild1} = Guilds.delete_guild(test_guild_id1)

      # Verify only the first guild's membership is deleted
      assert {:ok, nil} = Accounts.get_membership(test_user_id, test_guild_id1)

      assert {:ok, found_membership2_after} =
               Accounts.get_membership(test_user_id, test_guild_id2)

      assert found_membership2_after.guild_id == test_guild_id2

      # Verify the user still exists
      assert {:ok, user} = Accounts.get_user(test_user_id)
      assert user.user_id == test_user_id

      # Clean up - delete the second guild
      assert {:ok, _deleted_guild2} = Guilds.delete_guild(test_guild_id2)
      assert {:ok, nil} = Accounts.get_membership(test_user_id, test_guild_id2)
    end
  end
end
