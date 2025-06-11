defmodule TetoBot.MessageContext do
  @moduledoc """
  Builds conversation context for the LLM by reading recent Discord messages from
  `Nostrum.MessageCache`.

  The algorithm works in three stages:

  1. **Look-back** – Fetch at most `lookback_window` seconds of backlog (or all
     messages when the value is `:infinity`).  This caps the total amount of
     data we read from Mnesia.
  2. **Silence gap cut-off** – Walk backwards from the newest message and stop
     at the first pause longer than `silence_gap`.  This yields the most recent
     continuous conversation while discarding stale, unrelated threads.
  3. **Token budget trim** – Finally apply a token-aware filter so the selected
     messages never exceed `max_context_tokens`.

  Configuration keys under `:teto_bot`:
    - `:lookback_window`  – Seconds of history to load (`:infinity` to disable, default `86_400`, i.e. 24 h)
    - `:silence_gap`      – Seconds of allowed pause before we consider it a new topic (default `10_800`, i.e. 3 h)
    - `:max_context_tokens` – Maximum tokens of history to include (default `2 000`)
  """

  require Logger
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct.Message
  alias Nostrum.Bot
  alias TetoBot.Tokenizer

  @doc """
  Retrieves the conversation context for a channel using the three-stage
  algorithm described in the module documentation and returns a list of
  `{role, username, content}` tuples in chronological (oldest → newest) order.
  """
  @spec get_context(integer()) :: [{:user | :assistant, String.t(), String.t()}]
  def get_context(channel_id) do
    # How far back to look when fetching messages. Set to :infinity to disable.
    lookback_window = Application.get_env(:teto_bot, :lookback_window, 86_400)

    # Maximum silence (in seconds) allowed between consecutive messages before we
    # consider it a new topic and stop traversing further back in history.
    silence_gap = Application.get_env(:teto_bot, :silence_gap, 10_800)

    # Best-effort estimation for how many tokens of history we are willing to
    # send to the LLM.
    max_tokens = Application.get_env(:teto_bot, :max_context_tokens, 2_000)

    after_timestamp =
      case lookback_window do
        :infinity -> :infinity
        seconds when is_integer(seconds) -> DateTime.utc_now() |> DateTime.add(-seconds, :second)
      end

    messages =
      MessageCache.Mnesia.get_by_channel(channel_id, after_timestamp, :infinity)
      # Filter out empty messages
      |> Enum.filter(&(&1.content != ""))
      # Reject messages from command /feed
      |> Enum.reject(
        &(&1.content
          |> String.contains?("You fed Teto! Your intimacy with her increased"))
      )
      |> Enum.map(fn %Message{content: content, author: author, timestamp: timestamp} ->
        role = if author.id == Bot.get_bot_name(), do: :assistant, else: :user
        username = if role == :assistant, do: "Bot", else: author.username
        {role, username, content, timestamp}
      end)
      # Chronological ascending order (oldest → newest)
      |> Enum.sort_by(
        fn {_, _, _, timestamp} -> DateTime.to_unix(timestamp, :millisecond) end,
        :asc
      )

    # Stop at the first long silence to avoid dragging in messages from a
    # previous, unrelated conversation.
    messages = apply_silence_gap(messages, silence_gap)

    # Apply token-aware filtering after silence-gap trimming
    filtered_messages = apply_token_limit(messages, max_tokens)

    filtered_messages
    |> tap(fn msgs ->
      token_count = get_total_token_count(msgs)
      Logger.info("channel #{channel_id}: #{length(msgs)} messages, ~#{token_count} tokens")
    end)
    |> Enum.map(fn {role, username, content, _} -> {role, username, content} end)
  end

  @doc false
  # Traverses the list of messages **from newest to oldest** and stops when it
  # encounters a silence gap greater than `silence_gap` seconds. Returns the
  # messages that fall within the most recent continuous conversation slice.
  defp apply_silence_gap(messages, silence_gap) when is_integer(silence_gap) do
    messages_desc = Enum.reverse(messages)

    {selected_desc, _last_ts} =
      Enum.reduce_while(messages_desc, {[], nil}, fn {_, _, _, timestamp} = msg, {acc, last_ts} ->
        cond do
          # First message: always keep it
          last_ts == nil ->
            {:cont, {[msg | acc], timestamp}}

          DateTime.diff(last_ts, timestamp, :second) <= silence_gap ->
            # Gap within the allowed range – keep going
            {:cont, {[msg | acc], timestamp}}

          true ->
            # Gap too large – stop here
            {:halt, {acc, last_ts}}
        end
      end)

    Enum.reverse(selected_desc)
  end

  defp apply_silence_gap(messages, _), do: messages

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
