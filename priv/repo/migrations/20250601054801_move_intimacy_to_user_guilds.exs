defmodule TetoBot.Repo.Migrations.MoveIntimacyToUserGuilds do
  use Ecto.Migration

  def up do
    # Copy existing intimacy data from users to user_guilds
    # This will set the same intimacy score for all guilds that user is in
    execute("""
    UPDATE user_guilds
    SET intimacy = users.intimacy
    FROM users
    WHERE user_guilds.user_id = users.user_id
    AND users.intimacy IS NOT NULL
    AND users.intimacy > 0
    """)

    # Remove intimacy column from users table
    alter table(:users) do
      remove(:intimacy)
    end
  end

  def down do
    # Add intimacy back to users table
    alter table(:users) do
      add(:intimacy, :integer, default: 0)
    end

    # Copy intimacy data back from user_guilds to users
    # This will take the maximum intimacy score across all guilds for each user
    execute("""
    UPDATE users
    SET intimacy = subquery.max_intimacy
    FROM (
      SELECT user_id, MAX(intimacy) as max_intimacy
      FROM user_guilds
      WHERE intimacy > 0
      GROUP BY user_id
    ) AS subquery
    WHERE users.user_id = subquery.user_id
    """)
  end
end
