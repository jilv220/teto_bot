import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]
