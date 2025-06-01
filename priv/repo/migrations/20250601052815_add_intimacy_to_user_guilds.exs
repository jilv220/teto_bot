defmodule TetoBot.Repo.Migrations.AddIntimacyToUserGuilds do
  use Ecto.Migration

  def change do
    alter table(:user_guilds) do
      add(:intimacy, :integer, null: false, default: 0)
    end

    create(index(:user_guilds, [:guild_id, :intimacy]))
    drop(table(:leaderboard))
  end
end
