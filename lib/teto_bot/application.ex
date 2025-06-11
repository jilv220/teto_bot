defmodule TetoBot.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    TetoBot.Release.migrate()
    # Oban.Telemetry.attach_default_logger()

    bot_options = %{
      consumer: TetoBot.Consumer,
      intents: [:direct_messages, :guilds, :guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    redis_options = {
      Application.get_env(:teto_bot, :redis_url),
      name: :redix, socket_opts: Application.get_env(:teto_bot, :redis_socket_options)
    }

    # HTTP server configuration
    http_port = Application.get_env(:teto_bot, :http_port, 4000)
    cowboy_options = [port: http_port]

    children = [
      {Redix, redis_options},
      TetoBot.Repo,
      {Oban, Application.fetch_env!(:teto_bot, Oban)},
      {TetoBot.RateLimiter, [clean_period: :timer.minutes(1)]},
      TetoBot.Guilds.Cache,
      TetoBot.Channels.Cache,
      TetoBot.Tokenizer,
      # Finch instance for topgg API
      {Finch, name: :topgg_finch},
      {Nostrum.Bot, bot_options},
      {Plug.Cowboy, scheme: :http, plug: TetoBot.Web.Router, options: cowboy_options}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one)

    unless Application.get_env(:teto_bot, :env) == :test do
      # Warm Cache
      Task.start(fn -> TetoBot.Guilds.warm_cache() end)
    end

    Logger.info("HTTP server started on port #{http_port}")

    result
  end
end
