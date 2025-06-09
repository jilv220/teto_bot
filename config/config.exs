import Config

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [section_order: [:resources, :policies, :authorization, :domain, :execution]]
  ]

config :nostrum,
  ffmpeg: nil,
  caches: [
    messages: Nostrum.Cache.MessageCache.Mnesia
  ]

# Ash Domains
config :teto_bot, :ash_domains, [TetoBot.Guilds, TetoBot.Channels]

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
       {"0 */12 * * *", TetoBot.Accounts.DecayWorker}
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
  rate_limit_max_requests: 5,
  context_window: 1800,
  # Bot settings
  llm_model_name: "meta-llama/llama-4-maverick-17b-128e-instruct",
  llm_vision_model_name: "meta-llama/llama-4-maverick-17b-128e-instruct",
  llm_max_words: 100,
  llm_temperature: 0.8,
  llm_top_p: 1,
  llm_top_k: 45

config :teto_bot, TetoBot.Accounts.Decay,
  inactivity_threshold: :timer.hours(24 * 3),
  decay_amount: 4,
  minimum_intimacy: 5

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
#
# Quite neat, from Phoenix
import_config "#{config_env()}.exs"
