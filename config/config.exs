import Config

config :nostrum,
  ffmpeg: nil,
  caches: [
    messages: Nostrum.Cache.MessageCache.Mnesia
  ]

config :teto_bot, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: TetoBot.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       {"0 */12 * * *", TetoBot.Intimacy.DecayWorker}
     ]}
  ]

config :teto_bot,
  # Env
  env: config_env(),
  dev_guild_id: 1_374_179_000_192_339_979,
  # DB
  ecto_repos: [TetoBot.Repo],
  pool_size: 10,
  generators: [timestamp_type: :utc_datetime],
  # Rate limiting
  rate_limit_window: 60,
  rate_limit_max_requests: 10,
  context_window: 1800,
  # Bot settings
  llm_model_name: "meta-llama/llama-4-maverick-17b-128e-instruct",
  llm_vision_model_name: "meta-llama/llama-4-maverick-17b-128e-instruct",
  llm_max_words: 100,
  llm_temperature: 0.7,
  llm_top_p: 1,
  llm_top_k: 40

config :teto_bot, TetoBot.Intimacy, feed_cooldown_duration: :timer.hours(24)

config :teto_bot, TetoBot.Intimacy.Decay,
  check_interval: :timer.hours(12),
  inactivity_threshold: :timer.hours(24 * 3),
  decay_amount: 4,
  minimum_intimacy: 5

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
#
# Quite neat, from Phoenix
import_config "#{config_env()}.exs"
