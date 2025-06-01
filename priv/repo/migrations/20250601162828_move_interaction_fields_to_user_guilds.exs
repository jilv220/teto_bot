defmodule TetoBot.Repo.Migrations.MoveInteractionFieldsToUserGuilds do
  use Ecto.Migration

  def up do
    # Add the new fields to user_guilds table
    alter table(:user_guilds) do
      add(:last_interaction, :utc_datetime)
      add(:last_feed, :utc_datetime)
    end

    # Migrate existing data from users to user_guilds
    # This will copy the last_interaction and last_feed for each user to ALL their guild associations
    execute("""
    UPDATE user_guilds
    SET
      last_interaction = users.last_interaction,
      last_feed = users.last_feed
    FROM users
    WHERE user_guilds.user_id = users.user_id
    """)

    # Remove the fields from users table
    alter table(:users) do
      remove(:last_interaction)
      remove(:last_feed)
    end
  end

  def down do
    # Add fields back to users table
    alter table(:users) do
      add(:last_interaction, :utc_datetime)
      add(:last_feed, :utc_datetime)
    end

    # Migrate data back (taking the most recent interaction from any guild)
    execute("""
    UPDATE users
    SET
      last_interaction = subquery.max_last_interaction,
      last_feed = subquery.max_last_feed
    FROM (
      SELECT
        user_id,
        MAX(last_interaction) as max_last_interaction,
        MAX(last_feed) as max_last_feed
      FROM user_guilds
      GROUP BY user_id
    ) AS subquery
    WHERE users.user_id = subquery.user_id
    """)

    # Remove fields from user_guilds
    alter table(:user_guilds) do
      remove(:last_interaction)
      remove(:last_feed)
    end
  end
end
