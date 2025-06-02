defmodule TetoBot.Repo.Migrations.AddGuildIdToChannels do
  use Ecto.Migration

  def change do
    execute("DELETE FROM channels")

    alter table(:channels) do
      add(:guild_id, :integer, null: false)
    end

    create(index(:channels, [:guild_id]))

    # Add foreign key constraint with CASCADE delete
    # When a guild is deleted, all its channels should be deleted too
    alter table(:channels) do
      modify(:guild_id, references(:guilds, column: :guild_id, on_delete: :delete_all))
    end
  end
end
