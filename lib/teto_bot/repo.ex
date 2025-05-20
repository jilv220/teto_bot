defmodule TetoBot.Repo do
  use Ecto.Repo,
    otp_app: :teto_bot,
    adapter: Ecto.Adapters.SQLite3
end
