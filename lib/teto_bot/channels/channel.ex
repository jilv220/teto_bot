defmodule TetoBot.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:channel_id, :integer, autogenerate: false}
  schema "channels" do
    timestamps()
  end

  def changeset(channels, attrs) do
    channels
    |> cast(attrs, [:channel_id])
    |> validate_required([:channel_id])
    |> unique_constraint(:channel_id, name: :channels_pkey)
  end
end
