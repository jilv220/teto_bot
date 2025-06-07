defmodule TetoBot.Interactions.Ping do
  @moduledoc """
  Handles the /ping Discord slash command.
  """

  alias Nostrum.Struct.Interaction
  alias TetoBot.Interactions.Responses

  @spec handle_ping(Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /ping command - responds with "pong" to check if the bot is alive.
  """
  def handle_ping(interaction) do
    Responses.success(interaction, "pong", ephemeral: true)
  end
end
