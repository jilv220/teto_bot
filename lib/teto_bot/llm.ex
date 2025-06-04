defmodule TetoBot.LLM do
  @moduledoc """
  Main interface for LLM functionality. Coordinates between different modules.
  """

  require Logger
  alias TetoBot.LLM.{Client, MessageBuilder, ToolProcessor}

  @doc """
  Creates an OpenaiEx client using environment variables for API key and base URL.
  """
  defdelegate get_client(), to: Client

  @doc """
  Generates a response from the LLM using the conversation context, with support for tool calling.
  """
  def generate_response!(client, context) do
    with {:ok, messages} <- MessageBuilder.build_chat_messages(context),
         {:ok, response} <- create_standard_completion(client, messages) do
      process_llm_response(client, response, messages)
    else
      {:error, reason} ->
        Logger.error("Failed to generate response: #{inspect(reason)}")
        raise RuntimeError, message: "Failed to generate response from LLM"
    end
  end

  @doc """
  Generates a text summary of an image.
  """
  def summarize_image(client, image_url) do
    messages = MessageBuilder.build_vision_messages(image_url)
    chat_req = Client.build_chat_request(messages, :vision)

    case Client.create_completion(client, chat_req) do
      {:ok, %{"choices" => [%{"message" => %{"content" => summary}} | _]}}
      when is_binary(summary) ->
        {:ok, summary}

      {:ok, response} ->
        Logger.error("Unexpected vision response format: #{inspect(response)}")
        {:error, "Unexpected response format"}

      {:error, error} ->
        {:error, error}
    end
  end

  ## Private functions

  defp create_standard_completion(client, messages) do
    chat_req = Client.build_chat_request(messages, :standard)
    Client.create_completion(client, chat_req)
  end

  defp process_llm_response(client, response, messages) do
    case response do
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]} ->
        ToolProcessor.process_tool_calls(client, tool_calls, messages)

      %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
        Logger.info("Response from LLM: #{content}")
        content

      _ ->
        Logger.error("Unexpected response format from LLM: #{inspect(response)}")
        "I'm sorry, I couldn't process that request."
    end
  end
end
