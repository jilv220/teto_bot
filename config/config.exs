import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]

config :nostrum,
  ffmpeg: nil

config :teto_bot, ecto_repos: [TetoBot.Repo]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
#
# Quite neat, from Phoenix
import_config "#{config_env()}.exs"
