import Config

config :teto_bot, TetoBot.Repo,
  database: Path.expand("../teto_bot_test.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox
