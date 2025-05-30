defmodule TetoBot.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    TetoBot.Release.migrate()

    bot_options = %{
      consumer: TetoBot.Consumer,
      intents: [:direct_messages, :guilds, :guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    redis_options = {
      Application.get_env(:teto_bot, :redis_url),
      name: :redix, socket_opts: Application.get_env(:teto_bot, :redis_socket_options)
    }

    children = [
      {Redix, redis_options},
      TetoBot.Repo,
      TetoBot.Leaderboards.Sync,
      TetoBot.Leaderboards.Decay,
      {Nostrum.Bot, bot_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
