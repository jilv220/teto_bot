defmodule TetoBot.Leaderboards.Leaderboard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "leaderboard" do
    field(:guild_id, :integer)
    field(:user_id, :integer)
    field(:intimacy, :integer)
    timestamps()
  end

  def changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, [:guild_id, :user_id, :intimacy])
    |> validate_required([:guild_id, :user_id, :intimacy])
    |> unique_constraint([:guild_id, :user_id])
  end
end
