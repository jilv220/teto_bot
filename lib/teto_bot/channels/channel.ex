defmodule TetoBot.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:channel_id, :integer, autogenerate: false}
  schema "channels" do
    field(:guild_id, :integer)

    belongs_to(:guild, TetoBot.Guilds.Guild,
      foreign_key: :guild_id,
      references: :guild_id,
      define_field: false
    )

    timestamps()
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:channel_id, :guild_id])
    |> validate_required([:channel_id, :guild_id])
    |> unique_constraint(:channel_id, name: :channels_pkey)
    |> foreign_key_constraint(:guild_id)
  end
end
