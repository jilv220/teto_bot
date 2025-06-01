defmodule TetoBot.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add(:user_id, :bigint, primary_key: true)
      add(:last_interaction, :utc_datetime)
      add(:last_feed, :utc_datetime)
      add(:intimacy, :integer, default: 0)

      timestamps()
    end

    create(index(:users, [:last_interaction]))
  end
end
