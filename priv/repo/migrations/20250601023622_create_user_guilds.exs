defmodule TetoBot.Repo.Migrations.CreateUserGuilds do
  use Ecto.Migration

  def change do
    create table(:user_guilds, primary_key: false) do
      add(:user_id, references(:users, column: :user_id, type: :bigint), null: false)
      add(:guild_id, references(:guilds, column: :guild_id, type: :bigint), null: false)

      timestamps()
    end

    create(unique_index(:user_guilds, [:user_id, :guild_id]))
    create(index(:user_guilds, [:user_id]))
    create(index(:user_guilds, [:guild_id]))

    create(index(:users, [:last_feed]))
  end
end
