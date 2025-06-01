defmodule TetoBot.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :integer, autogenerate: false}
  schema "users" do
    many_to_many(:guilds, TetoBot.Guilds.Guild,
      join_through: "user_guilds",
      join_keys: [user_id: :user_id, guild_id: :guild_id]
    )

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:user_id])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id, name: :users_pkey)
  end
end
