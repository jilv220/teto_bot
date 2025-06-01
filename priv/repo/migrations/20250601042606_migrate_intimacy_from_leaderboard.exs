defmodule TetoBot.Repo.Migrations.MigrateIntimacyFromLeaderboard do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Use raw SQL for the data migration
    execute("""
    WITH user_intimacy AS (
      SELECT
        user_id,
        SUM(intimacy) as total_intimacy,
        MIN(inserted_at) as first_seen,
        MAX(updated_at) as last_updated
      FROM leaderboard
      GROUP BY user_id
    )
    INSERT INTO users (user_id, intimacy, inserted_at, updated_at)
    SELECT
      user_id,
      total_intimacy,
      COALESCE(first_seen, NOW()),
      COALESCE(last_updated, NOW())
    FROM user_intimacy
    ON CONFLICT (user_id)
    DO UPDATE SET
      intimacy = EXCLUDED.intimacy,
      updated_at = EXCLUDED.updated_at
    """)

    # Insert guilds from leaderboard
    execute("""
    INSERT INTO guilds (guild_id, inserted_at, updated_at)
    SELECT DISTINCT
      guild_id,
      MIN(inserted_at) as first_seen,
      MAX(updated_at) as last_updated
    FROM leaderboard
    GROUP BY guild_id
    ON CONFLICT (guild_id) DO NOTHING
    """)

    # Insert user_guild relationships
    execute("""
    INSERT INTO user_guilds (user_id, guild_id, inserted_at, updated_at)
    SELECT
      user_id,
      guild_id,
      COALESCE(inserted_at, NOW()),
      COALESCE(updated_at, NOW())
    FROM leaderboard
    ON CONFLICT (user_id, guild_id) DO NOTHING
    """)

    # Verify the migration - Fixed syntax
    execute("""
    DO $$
    DECLARE
      leaderboard_total INTEGER;
      users_total INTEGER;
    BEGIN
      SELECT SUM(intimacy) INTO leaderboard_total FROM leaderboard;
      SELECT SUM(intimacy) INTO users_total FROM users;

      RAISE NOTICE 'Migration verification:';
      RAISE NOTICE 'Leaderboard total intimacy: %', leaderboard_total;
      RAISE NOTICE 'Users total intimacy: %', users_total;

      IF leaderboard_total != users_total THEN
        RAISE EXCEPTION 'Migration failed: intimacy totals do not match!';
      END IF;

      RAISE NOTICE 'Migration completed successfully!';
    END $$;
    """)
  end

  def down do
    # Rollback - be careful with this!
    execute("UPDATE users SET intimacy = 0")
    execute("DELETE FROM user_guilds")
    IO.puts("Migration rolled back")
  end
end
