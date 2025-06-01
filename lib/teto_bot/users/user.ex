defmodule TetoBot.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :integer, autogenerate: false}
  schema "users" do
    field(:last_interaction, :utc_datetime)
    field(:last_feed, :utc_datetime)

    many_to_many(:guilds, TetoBot.Guilds.Guild,
      join_through: "user_guilds",
      join_keys: [user_id: :user_id, guild_id: :guild_id]
    )

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:user_id, :last_interaction, :last_feed])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id, name: :users_pkey)
  end
end
