defmodule TetoBot.Application do
  require Logger

  use Application

  @impl true
  def start(_type, _args) do
    :ets.new(:rate_limit, [:set, :public, :named_table])
    Logger.info("Initialized :rate_limit ETS table")

    bot_options = %{
      consumer: TetoBot.Consumer,
      intents: [:direct_messages, :guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    children = [
      TetoBot.Repo,
      {TetoBot.MessageContext, []},
      {Nostrum.Bot, bot_options}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
