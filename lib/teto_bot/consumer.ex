require Logger

defmodule TetoBot.Consumer do
  @behaviour Nostrum.Consumer

  alias Nostrum.Api.Message
  alias TetoBot.TextGenerator

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    try do
      case msg.content do
        "!ping" ->
          Message.create(msg.channel_id, "pong!")

        text ->
          response = TextGenerator.generate_response(text)
          Message.create(msg.channel_id, response)
      end
    rescue
      e in RuntimeError ->
        Logger.error("Text generation error: #{inspect(e)}")

        Message.create(msg.channel_id,
          content: "Oops, something went wrong! Try again, okay?"
        )

        :noop
    end
  end

  # Ignore any other events
  def handle_event(_), do: :ok
end
