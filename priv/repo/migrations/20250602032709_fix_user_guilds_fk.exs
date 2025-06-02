defmodule TetoBot.Repo.Migrations.FixUserGuildsFk do
  use Ecto.Migration

  def change do
    # Drop existing constraints
    drop(constraint(:user_guilds, "user_guilds_guild_id_fkey"))
    drop(constraint(:user_guilds, "user_guilds_user_id_fkey"))

    alter table(:user_guilds) do
      modify(:guild_id, references(:guilds, column: :guild_id, on_delete: :delete_all))
      modify(:user_id, references(:users, column: :user_id, on_delete: :delete_all))
    end
  end
end
