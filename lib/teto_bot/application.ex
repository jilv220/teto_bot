defmodule TetoBot.Application do
  use Application

  alias TetoBot.TextGenerator

  @impl true
  def start(_type, _args) do
    bot_options = %{
      consumer: TetoBot.Consumer,
      intents: [:direct_messages, :guild_messages, :message_content],
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    children = [
      {Nostrum.Bot, bot_options},
      {Nx.Serving, serving: TextGenerator.serving(), name: TetoBot.Serving, batch_timeOut: 1000}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
