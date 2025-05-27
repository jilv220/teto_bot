import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :teto_bot, TetoBot.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
end

if config_env() == :prod do
  redis_url =
    System.get_env("REDIS_URL") ||
      raise """
      environment variable REDIS_URL is missing.
      """

  config :teto_bot,
    redis_url: redis_url
end
