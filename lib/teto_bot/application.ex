defmodule TetoBot.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    TetoBot.Release.migrate()
    Oban.Telemetry.attach_default_logger()

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
      {Oban, Application.fetch_env!(:teto_bot, Oban)},
      TetoBot.RateLimiter,
      TetoBot.Guilds.Cache,
      TetoBot.Channels.Cache,
      TetoBot.Intimacy.Decay,
      {Nostrum.Bot, bot_options}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one)

    # Warm Cache
    Task.start(fn -> TetoBot.Guilds.warm_cache() end)
    result
  end
end
