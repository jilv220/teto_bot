import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]

config :teto_bot, TetoBot.Repo,
  url:
    System.get_env(
      "DATABASE_URL",
      "ecto://test_user:test_password@localhost:5433/teto_bot_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox

config :teto_bot, TetoBot.Channels.Cache, TetoBot.Channels.CacheMock
config :teto_bot, :repo, TetoBot.RepoMock

## TODO: Replace this with Mox!!!
config :teto_bot,
  redis_url: System.get_env("REDIS_URL", "redis://:dev_password@localhost:6379"),
  redis_socket_options: []
