defmodule TetoBot.MessageContext do
  @moduledoc """
  A module for retrieving channel-wide message context using Nostrum's MessageCache.

  Fetches messages for a channel within a configurable time window and formats them
  with roles (:user or :assistant). Includes token-aware filtering to stay within
  token limits while maintaining conversation quality.

  Configuration keys under `:teto_bot`:
    - `:context_window`: Time window in seconds for retrieving messages (default: 300)
    - `:max_context_tokens`: Maximum tokens for context (default: 28000)
  """

  require Logger
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct.Message
  alias Nostrum.Bot
  alias TetoBot.Tokenizer

  @doc """
  Retrieves the conversation context for a channel within the time window.
  Returns a list of {role, username, content} tuples in chronological order,
  filtered to stay within token limits.
  """
  @spec get_context(integer()) :: [{:user | :assistant, String.t(), String.t()}]
  def get_context(channel_id) do
    window = Application.get_env(:teto_bot, :context_window, 300)
    max_tokens = Application.get_env(:teto_bot, :max_context_tokens, 28_000)

    after_timestamp = DateTime.utc_now() |> DateTime.add(-window, :second)

    messages =
      MessageCache.Mnesia.get_by_channel(channel_id, after_timestamp, :infinity)
      # Filter out empty messages
      |> Enum.filter(&(&1.content != ""))
      # Reject messages from /feed
      |> Enum.reject(
        &(&1.content
          |> String.contains?("You fed Teto! Your intimacy with her increased"))
      )
      |> Enum.map(fn %Message{content: content, author: author, timestamp: timestamp} ->
        role = if author.id == Bot.get_bot_name(), do: :assistant, else: :user
        username = if role == :assistant, do: "Bot", else: author.username
        {role, username, content, timestamp}
      end)
      |> Enum.sort_by(
        fn {_, _, _, timestamp} -> DateTime.to_unix(timestamp, :millisecond) end,
        :asc
      )

    # Apply token-aware filtering
    filtered_messages = apply_token_limit(messages, max_tokens)

    filtered_messages
    |> tap(fn msgs ->
      token_count = get_total_token_count(msgs)
      Logger.info("channel #{channel_id}: #{length(msgs)} messages, ~#{token_count} tokens")
    end)
    |> Enum.map(fn {role, username, content, _} -> {role, username, content} end)
  end

  @doc false
  # Applies token-aware filtering to keep messages under the token limit.
  # Prioritizes recent messages.
  defp apply_token_limit(messages, max_tokens) do
    reversed_messages = Enum.reverse(messages)

    {selected_messages, _total_tokens} =
      Enum.reduce_while(reversed_messages, {[], 0}, fn message, {acc, token_count} ->
        {_role, _username, content, _timestamp} = message

        message_tokens = get_token_count(content)
        new_token_count = token_count + message_tokens

        if new_token_count > max_tokens do
          {:halt, {acc, token_count}}
        else
          {:cont, {[message | acc], new_token_count}}
        end
      end)

    selected_messages
  end

  @doc false
  # Gets the number of tokens in a message.
  @spec get_token_count(String.t()) :: integer()
  defp get_token_count(content) do
    Tokenizer.get_token_count(content)
  end

  @doc false
  # Estimates total token count for a list of messages.
  defp get_total_token_count(messages) do
    Enum.reduce(messages, 0, fn message, acc ->
      {_role, _username, content, _timestamp} = message
      acc + get_token_count(content)
    end)
  end
end
