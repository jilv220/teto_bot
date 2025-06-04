defmodule TetoBot.LLM.ToolProcessor do
  @moduledoc """
  Handles tool call processing and execution.
  """

  require Logger
  alias TetoBot.LLM.{Client, Tools}

  def process_tool_calls(client, tool_calls, messages) do
    with {:ok, updated_messages} <- add_assistant_message_with_tools(tool_calls, messages),
         {:ok, final_messages} <- execute_tools_and_add_results(tool_calls, updated_messages),
         {:ok, response} <- get_final_response(client, final_messages) do
      extract_content_from_response(response, "tool use")
    else
      {:error, reason} ->
        Logger.error("Tool processing failed: #{inspect(reason)}")
        "I encountered an error while processing your request."
    end
  end

  defp add_assistant_message_with_tools(tool_calls, messages) do
    assistant_message = %{
      "role" => "assistant",
      "content" => nil,
      "tool_calls" => tool_calls
    }

    {:ok, [assistant_message | messages]}
  end

  defp execute_tools_and_add_results(tool_calls, messages) do
    tool_results = Enum.map(tool_calls, &execute_single_tool/1)
    final_messages = Enum.reverse(tool_results ++ Enum.reverse(messages))
    {:ok, final_messages}
  end

  defp execute_single_tool(tool_call) do
    function = tool_call["function"]
    function_name = function["name"]

    args = safe_decode_json(function["arguments"])

    case Tools.execute_tool(function_name, args) do
      {:ok, result} ->
        build_tool_result(tool_call["id"], function_name, Jason.encode!(result))

      {:error, reason} ->
        Logger.error("Tool execution failed for #{function_name}: #{inspect(reason)}")
        build_tool_result(tool_call["id"], function_name, "Error: #{inspect(reason)}")
    end
  end

  defp safe_decode_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, decoded} ->
        decoded

      {:error, _} ->
        Logger.warning("Failed to decode tool arguments: #{json_string}")
        %{}
    end
  end

  defp build_tool_result(tool_call_id, function_name, content) do
    %{
      "tool_call_id" => tool_call_id,
      "role" => "tool",
      "name" => function_name,
      "content" => content
    }
  end

  defp get_final_response(client, messages) do
    chat_req = Client.build_chat_request(messages, :tool_followup)
    Client.create_completion(client, chat_req)
  end

  defp extract_content_from_response(response, context) do
    case response do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
        Logger.info("Response from LLM after #{context}: #{content}")
        content

      _ ->
        Logger.error("Unexpected response format after #{context}: #{inspect(response)}")
        "I encountered an error while processing your request."
    end
  end
end
