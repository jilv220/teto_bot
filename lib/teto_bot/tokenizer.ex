defmodule TetoBot.Tokenizer do
  @moduledoc """
  HTTP client for tokenization API calls.

  Makes HTTP POST requests to the tokenizer API endpoint to get token counts.
  """
  require Logger

  @doc """
  Gets the number of tokens in a string by calling the tokenizer API.
  """
  @spec get_token_count(String.t()) :: integer()
  def get_token_count(content) do
    call_tokenizer_api(content)
  end

  # Private functions

  defp call_tokenizer_api(content) do
    base_url = get_api_base_url()
    url = "#{base_url}/api/tokens"

    body = Jason.encode!(%{"text" => content})

    headers = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, :tokenizer_finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"token_count" => count, "text_length" => _length}} when is_integer(count) ->
            count

          {:ok, response} ->
            Logger.warning("Unexpected tokenizer API response format: #{inspect(response)}")
            0

          {:error, _} ->
            Logger.error("Failed to decode tokenizer API response: #{response_body}")
            0
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("Tokenizer API returned status #{status}: #{body}")
        0

      {:error, error} ->
        Logger.error("Failed to call tokenizer API: #{inspect(error)}")
        0
    end
  end

  defp get_api_base_url do
    System.get_env("API_BASE_URL") ||
      Application.get_env(:teto_bot, :api_base_url) ||
      "http://localhost:8000"
  end
end
