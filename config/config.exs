import Config

config :logger, :console, metadata: [:shard, :guild, :channel, :bot]

config :nostrum,
  ffmpeg: nil

config :nx, :default_backend, EXLA.Backend
