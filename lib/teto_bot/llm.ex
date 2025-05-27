defmodule TetoBot.LLM do
  @moduledoc """
  Interfaces with an LLM API to generate responses as Kasane Teto.

  Configuration keys under `:teto_bot`:
    - `:llm_model_name`: LLM model name (default: "grok-3-mini")
    - `:llm_sys_prompt`: System prompt defining Teto's personality (default: see below)
    - `:llm_max_words`: Maximum words in response (default: 50)
  """

  require Logger

  alias OpenaiEx.MsgContent
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage

  alias TetoBot.LLM

  @doc """
  Creates an OpenaiEx client using environment variables for API key and base URL.
  """
  # @spec get_client() :: OpenaiEx.t()
  def get_client do
    apikey = System.fetch_env!("LLM_API_KEY")
    # base_url = System.fetch_env!("LLM_BASE_URL")

    OpenaiEx.new(apikey)
    # |> OpenaiEx.with_base_url(base_url)
    |> OpenaiEx.with_receive_timeout(30_000)
  end

  @doc """
  Generates a response from the LLM using the conversation context.

  ## Parameters
    - openai: OpenaiEx client
    - context: List of message strings in chronological order
  """
  def generate_response(openai, context) do
    {:ok, sys_prompt} = LLM.Context.get_system_prompt()

    model_name = Application.get_env(:teto_bot, :llm_model_name, "grok-3-mini")
    max_words = Application.get_env(:teto_bot, :llm_max_words, 50)

    temperature = Application.get_env(:teto_bot, :llm_temperature, 0.7)
    top_p = Application.get_env(:teto_bot, :llm_top_p, 0.9)
    top_k = Application.get_env(:teto_bot, :llm_top_k, 40)

    messages =
      [
        ChatMessage.system(sys_prompt <> "\nKeep responses under #{max_words} words.")
        | Enum.map(context, fn
            {:user, username, content} ->
              ChatMessage.user("from " <> username <> ": " <> content)

            {:assistant, _username, content} ->
              ChatMessage.assistant(content)
          end)
      ]

    chat_req =
      Chat.Completions.new(
        model: model_name,
        messages: messages,
        temperature: temperature,
        top_p: top_p,
        top_k: top_k
      )

    case Chat.Completions.create(openai, chat_req) do
      {:ok,
       %{
         "choices" =>
           [%{"message" => %{"content" => content}} | _] =
               _resp
       }} ->
        Logger.info("Response from LLM: #{content}")
        content

      {:error, error} ->
        Logger.error("LLM API error: #{inspect(error)}")
        raise RuntimeError, message: "Failed to generate response from LLM"
    end
  end

  @doc """
  Generates a text summary of an image.

  ## Parameters
    - openai: OpenaiEx client
    - image_url: URL of the image to summarize

  ## Returns
    - {:ok, summary} if successful
    - {:error, reason} if the summarization fails
  """
  def summarize_image(openai, image_url) do
    vision_model = Application.get_env(:teto_bot, :llm_vision_model_name, "grok-2-vision-latest")

    messages = [
      ChatMessage.user([
        %{
          type: "image_url",
          # Library needs to update, i ll make a PR if no one made one already..
          image_url: %{
            url: image_url,
            detail: "high"
          }
        },
        MsgContent.text(
          "Summarize this image, try to identify whether the character is Kasane Teto,
           and reply in the format of 'User uploaded a image...' "
        )
      ])
    ]

    chat_req =
      Chat.Completions.new(
        model: vision_model,
        messages: messages,
        temperature: 0.01
      )

    case Chat.Completions.create(openai, chat_req) do
      {:ok, %{"choices" => [%{"message" => %{"content" => summary}} | _]}} ->
        {:ok, summary}

      {:error, error} ->
        {:error, error}
    end
  end
end
