defmodule TetoBot.Repo.Migrations.AddMessageCreditsToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add(:message_credits, :integer, null: false, default: 10)
    end
  end

  def down do
    alter table(:users) do
      remove(:message_credits)
    end
  end
end
