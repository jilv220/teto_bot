defmodule TetoBot.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  def change do
    create table(:guilds, primary_key: false) do
      add(:guild_id, :bigint, primary_key: true)
      timestamps()
    end
  end
end
