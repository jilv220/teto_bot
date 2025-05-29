defmodule TetoBot.Repo.Migrations.FixLeaderboardConstraints do
  use Ecto.Migration

  def change do
    drop(constraint(:leaderboard, "leaderboard_pkey"))
    drop_if_exists(index(:leaderboard, [:guild_id, :user_id]))

    # Create a new composite primary key
    alter table(:leaderboard) do
      modify(:guild_id, :bigint, primary_key: true)
      modify(:user_id, :bigint, primary_key: true)
    end
  end
end
