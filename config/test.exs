import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]

config :myapp, MyApp.Repo,
  url:
    System.get_env(
      "DATABASE_URL",
      "ecto://test_user:test_password@postgres_test:5432/teto_bot_test"
    ),
  pool: Ecto.Adapters.SQL.Sandbox
