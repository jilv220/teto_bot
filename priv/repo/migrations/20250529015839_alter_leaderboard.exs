defmodule TetoBot.Repo.Migrations.AlterLeaderboard do
  use Ecto.Migration

  def change do
    alter table(:leaderboard) do
      modify(:intimacy, :integer, default: 0, null: false)
    end
  end
end
