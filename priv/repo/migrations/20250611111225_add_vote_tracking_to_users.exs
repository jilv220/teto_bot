defmodule TetoBot.Repo.Migrations.AddVoteTrackingToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:last_voted_at, :utc_datetime, null: true)
    end

    create index(:users, [:last_voted_at])
  end
end
