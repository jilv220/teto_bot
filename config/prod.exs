import Config

config :logger, :console, level: :info, metadata: [:shard, :guild, :channel, :bot, :module]
