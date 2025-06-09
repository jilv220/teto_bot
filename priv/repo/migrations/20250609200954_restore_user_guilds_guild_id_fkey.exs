defmodule TetoBot.Repo.Migrations.RestoreUserGuildsGuildIdFkey do
  use Ecto.Migration

  def up do
    # Add the missing foreign key constraint that was dropped by the Ash guild migration
    # This constraint should have been restored but was forgotten
    alter table(:user_guilds) do
      modify(:guild_id, references(:guilds, column: :guild_id, on_delete: :delete_all))
    end
  end

  def down do
    # Remove the foreign key constraint
    drop(constraint(:user_guilds, "user_guilds_guild_id_fkey"))
  end
end
