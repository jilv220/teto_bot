defmodule TetoBot.Repo.Migrations.AddPrimaryKeyToUserGuilds do
  use Ecto.Migration

  def up do
    # Drop the existing unique index since we're replacing it with a primary key
    drop(unique_index(:user_guilds, [:user_id, :guild_id]))

    # Add composite primary key
    alter table(:user_guilds) do
      modify(:user_id, :bigint, primary_key: true)
      modify(:guild_id, :bigint, primary_key: true)
    end
  end

  def down do
    # Remove the primary key constraint
    drop(constraint(:user_guilds, "user_guilds_pkey"))

    # Recreate the unique index
    create(unique_index(:user_guilds, [:user_id, :guild_id]))
  end
end
