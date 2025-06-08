defmodule TetoBot.Accounts.UserGuild do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "user_guilds" do
    field(:user_id, :integer, primary_key: true)
    field(:guild_id, :integer, primary_key: true)
    field(:intimacy, :integer, default: 0)
    field(:last_message_at, :utc_datetime)
    field(:last_feed, :utc_datetime)

    timestamps()
  end

  def changeset(user_guild, attrs) do
    user_guild
    |> cast(attrs, [:user_id, :guild_id, :intimacy, :last_message_at, :last_feed])
    |> validate_required([:user_id, :guild_id])
    |> validate_number(:intimacy, greater_than_or_equal_to: 0)
  end
end
