defmodule TetoBot.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    TetoBot.Release.migrate()

    :ets.new(:rate_limit, [:set, :public, :named_table])
    Logger.info("Initialized :rate_limit ETS table")

    bot_options = %{
      consumer: TetoBot.Consumer,
      intents: [:direct_messages, :guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    children = [
      {Redix, {Application.get_env(:teto_bot, :redis_url), name: :redix}},
      TetoBot.Repo,
      {Nostrum.Bot, bot_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
