defmodule TetoBot.Interactions do
  @moduledoc """
  Handles Discord interaction-related functionality, dispatching commands to appropriate handlers.
  """

  alias Nostrum.Struct.{Interaction, User}

  alias TetoBot.Interactions.{
    Blacklist,
    Feed,
    Help,
    Leaderboard,
    Ping,
    Teto,
    Whitelist
  }

  @spec handle_interaction(Interaction.t(), any()) :: :ok | Nostrum.Api.error()
  @doc """
  Dispatches Discord interactions to the appropriate command handlers.
  """
  def handle_interaction(%Interaction{data: %{name: "ping"}} = interaction, _ws_state) do
    Ping.handle_ping(interaction)
  end

  def handle_interaction(%Interaction{data: %{name: "help"}} = interaction, _ws_state) do
    Help.handle_help(interaction)
  end

  def handle_interaction(%Interaction{data: %{name: "teto"}} = interaction, _ws_state) do
    Teto.handle_teto(interaction)
  end

  def handle_interaction(
        %Interaction{
          data: %{name: "feed"},
          user: %User{id: user_id},
          guild_id: guild_id,
          channel_id: channel_id
        } = interaction,
        _ws_state
      ) do
    Feed.handle_feed(interaction, user_id, guild_id, channel_id)
  end

  def handle_interaction(
        %Interaction{data: %{name: "leaderboard"}, guild_id: guild_id} = interaction,
        _ws_state
      ) do
    Leaderboard.handle_leaderboard(interaction, guild_id)
  end

  def handle_interaction(%Interaction{data: %{name: "whitelist"}} = interaction, _ws_state) do
    Whitelist.handle_whitelist(interaction)
  end

  def handle_interaction(%Interaction{data: %{name: "blacklist"}} = interaction, _ws_state) do
    Blacklist.handle_blacklist(interaction)
  end

  def handle_interaction(_interaction, _ws_state), do: :ok
end
