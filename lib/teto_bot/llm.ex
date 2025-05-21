defmodule TetoBot.LLM do
  @moduledoc """
  Interfaces with an LLM API to generate responses as Kasane Teto.

  Configuration keys under `:teto_bot`:
    - `:llm_model_name`: LLM model name (default: "grok-3-mini")
    - `:llm_sys_prompt`: System prompt defining Teto's personality (default: see below)
    - `:llm_max_words`: Maximum words in response (default: 50)
  """

  require Logger
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

  @doc """
  Creates an OpenaiEx client using environment variables for API key and base URL.
  """
  # @spec get_client() :: OpenaiEx.t()
  def get_client do
    apikey = System.fetch_env!("LLM_API_KEY")
    base_url = System.fetch_env!("LLM_BASE_URL")

    OpenaiEx.new(apikey)
    |> OpenaiEx.with_base_url(base_url)
  end

  @doc """
  Generates a response from the LLM using the conversation context.

  ## Parameters
    - openai: OpenaiEx client
    - context: List of message strings in chronological order
  """
  def generate_response(openai, context) do
    sys_prompt = Application.get_env(:teto_bot, :llm_sys_prompt, "")
    model_name = Application.get_env(:teto_bot, :llm_model_name, "grok-3-mini")
    max_words = Application.get_env(:teto_bot, :llm_max_words, 50)

    messages = [
      ChatMessage.system(sys_prompt <> "\nKeep responses under #{max_words} words.")
      | Enum.map(context, &ChatMessage.user/1)
    ]

    chat_req =
      Chat.Completions.new(
        model: model_name,
        messages: messages,
        reasoning_effort: "low"
      )

    case Chat.Completions.create(openai, chat_req) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        Logger.info("Response from LLM: #{content}")
        content

      {:error, error} ->
        Logger.error("LLM API error: #{inspect(error)}")
        raise RuntimeError, message: "Failed to generate response from LLM"
    end
  end
end
