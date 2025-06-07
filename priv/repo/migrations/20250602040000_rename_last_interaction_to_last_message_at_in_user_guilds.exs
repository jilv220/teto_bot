defmodule TetoBot.Repo.Migrations.RenameLastInteractionToLastMessageAtInUserGuilds do
  use Ecto.Migration

  def change do
    rename(table(:user_guilds), :last_interaction, to: :last_message_at)
  end
end
