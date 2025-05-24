import Config

config :logger, :console, level: :info, metadata: [:shard, :guild, :channel, :bot]

config :teto_bot, TetoBot.Repo,
  url: System.fetch_env!("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  ssl: true
