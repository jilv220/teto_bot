defmodule TetoBot.Guilds.Guild do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:guild_id, :integer, autogenerate: false}
  schema "guilds" do
    timestamps()
  end

  def changeset(channels, attrs) do
    channels
    |> cast(attrs, [:guild_id])
    |> validate_required([:guild_id])
    |> unique_constraint(:guild_id, name: :guilds_pkey)
  end
end
