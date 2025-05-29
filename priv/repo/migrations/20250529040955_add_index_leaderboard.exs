defmodule TetoBot.Repo.Migrations.AddIndexLeaderboard do
  use Ecto.Migration

  def change do
    create(unique_index(:leaderboard, [:guild_id, :user_id]))
  end
end
