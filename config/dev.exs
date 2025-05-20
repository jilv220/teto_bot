import Config

config :teto_bot, TetoBot.Repo,
  database: Path.expand("../teto_bot_dev.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true
