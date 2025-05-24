import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]

config :teto_bot, TetoBot.Repo,
  url: System.get_env("DATABASE_URL", "ecto://dev_user:dev_password@localhost:5432/teto_bot_dev"),
  pool_size: 10
