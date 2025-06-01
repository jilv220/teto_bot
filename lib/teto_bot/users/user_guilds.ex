defmodule TetoBot.Users.UserGuild do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "user_guilds" do
    field(:user_id, :integer, primary_key: true)
    field(:guild_id, :integer, primary_key: true)
    field(:intimacy, :integer, default: 0)

    timestamps()
  end

  def changeset(user_guild, attrs) do
    user_guild
    |> cast(attrs, [:user_id, :guild_id, :intimacy])
    |> validate_required([:user_id, :guild_id])
    |> validate_number(:intimacy, greater_than_or_equal_to: 0)
  end
end
