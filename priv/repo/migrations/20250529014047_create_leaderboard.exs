defmodule TetoBot.Repo.Migrations.CreateLeaderboard do
  use Ecto.Migration

  def change do
    create table(:leaderboard, primary_key: false) do
      add(:user_id, :bigint, primary_key: true)
      add(:guild_id, :bigint, null: false)
      add(:intimacy, :integer, default: 0)
      timestamps()
    end
  end
end
