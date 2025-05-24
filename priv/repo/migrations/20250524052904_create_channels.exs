defmodule TetoBot.Repo.Migrations.CreateChannels do
  use Ecto.Migration

  def change do
    create table(:channels, primary_key: false) do
      add(:channel_id, :bigint, primary_key: true)
      timestamps()
    end
  end
end
