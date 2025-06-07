defmodule TetoBot.LLM.Client do
  @moduledoc """
  OpenAI client management and API communication.
  """

  require Logger
  alias OpenaiEx.Chat
  alias TetoBot.LLM.Config

  def get_client do
    apikey = System.fetch_env!("LLM_API_KEY")
    base_url = System.fetch_env!("LLM_BASE_URL")

    OpenaiEx.new(apikey)
    |> OpenaiEx.with_base_url(base_url)
    |> OpenaiEx.with_receive_timeout(30_000)
  end

  def create_completion(client, chat_request) do
    case Chat.Completions.create(client, chat_request) do
      {:ok, response} ->
        {:ok, response}

      {:error, error} ->
        Logger.error("LLM API error: #{inspect(error)}")
        {:error, error}
    end
  end

  def build_chat_request(messages, :standard) do
    config = Config.get_all()

    Chat.Completions.new(
      model: config.llm_model_name,
      messages: messages,
      temperature: config.llm_temperature,
      top_p: config.llm_top_p,
      top_k: config.llm_top_k,
      tools: TetoBot.LLM.Tools.tools(),
      tool_choice: "auto",
      max_tokens: 30_000
    )
  end

  def build_chat_request(messages, :vision) do
    Chat.Completions.new(
      model: Config.get(:llm_vision_model_name),
      messages: messages,
      temperature: Config.get(:llm_vision_temperature)
    )
  end

  def build_chat_request(messages, :tool_followup) do
    config = Config.get_all()

    Chat.Completions.new(
      model: config.llm_model_name,
      messages: messages,
      temperature: config.llm_temperature,
      top_p: config.llm_top_p,
      top_k: config.llm_top_k
    )
  end
end
