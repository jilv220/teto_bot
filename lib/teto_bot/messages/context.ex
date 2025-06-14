defmodule TetoBot.Messages.Context do
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
  3. **Summarization** – If there are too many messages, use a smaller model to
     summarize older portions of the conversation while preserving the most recent
     messages for full context.

  Configuration keys under `:teto_bot`:
    - `:lookback_window`  – Seconds of history to load (`:infinity` to disable, default `86_400`, i.e. 24 h)
    - `:silence_gap`      – Seconds of allowed pause before we consider it a new topic (default `10_800`, i.e. 3 h)
    - `:summarization_threshold` – Number of messages to trigger summarization (default `50`)
    - `:recent_messages_keep` – Number of recent messages to keep unsummarized (default `10`)
  """

  require Logger
  alias TetoBot.Interactions.Leaderboard
  alias TetoBot.Interactions.Feed
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct.Message
  alias Nostrum.Bot
  alias TetoBot.LLM
  alias TetoBot.Tokenizer

  @doc """
  Retrieves the conversation context for a channel using the three-stage
  algorithm described in the module documentation and returns a list of
  `{role, username, content}` tuples in chronological (oldest → newest) order.
  """
  @spec get_context(integer()) :: [{:user | :assistant, String.t(), String.t()}]
  def get_context(channel_id) do
    config = Application.get_env(:teto_bot, TetoBot.Messages.Context, [])

    # How far back to look when fetching messages. Set to :infinity to disable.
    lookback_window = Keyword.get(config, :lookback_window, 60 * 60 * 24)

    # Maximum silence (in seconds) allowed between consecutive messages before we
    # consider it a new topic and stop traversing further back in history.
    silence_gap = Keyword.get(config, :silence_gap, 60 * 60 * 3)

    # Number of messages that triggers summarization
    summarization_threshold = Keyword.get(config, :summarization_threshold, 50)

    # Number of recent messages to keep unsummarized
    recent_messages_keep = Keyword.get(config, :recent_messages_keep, 10)

    after_timestamp =
      case lookback_window do
        :infinity -> :infinity
        seconds when is_integer(seconds) -> DateTime.utc_now() |> DateTime.add(-seconds, :second)
      end

    messages =
      MessageCache.Mnesia.get_by_channel(channel_id, after_timestamp, :infinity)
      # Filter out empty messages
      |> Enum.filter(&(&1.content != ""))
      # Reject messages from command /feed and /leaderboard
      |> Enum.reject(
        &(String.contains?(&1.content, Feed.build_feed_success_message()) or
            String.contains?(&1.content, Feed.build_cooldown_message()) or
            String.contains?(&1.content, Leaderboard.build_leaderboard_title()))
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

    # Apply summarization if there are too many messages
    filtered_messages =
      apply_summarization(messages, summarization_threshold, recent_messages_keep)

    filtered_messages
    |> tap(fn msgs ->
      message_count = length(msgs)
      total_tokens = count_total_tokens(msgs)

      Logger.info("channel #{channel_id}: #{message_count} messages, ~#{total_tokens} tokens")
    end)
    |> Enum.map(fn {role, username, content, _} -> {role, username, content} end)
  end

  @doc false
  # Traverses the list of messages **from newest to oldest** and stops when it
  # encounters a silence gap greater than `silence_gap` seconds. Returns the
  # messages that fall within the most recent continuous conversation slice.
  defp apply_silence_gap(messages, silence_gap) when is_integer(silence_gap) do
    messages_desc = Enum.reverse(messages)

    {selected_asc, _last_ts} =
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

    selected_asc
  end

  defp apply_silence_gap(messages, _), do: messages

  @doc false
  # Applies summarization when there are too many messages.
  # Keeps the most recent messages and summarizes older ones.
  defp apply_summarization(messages, threshold, recent_keep) when length(messages) > threshold do
    {older_messages, recent_messages} = Enum.split(messages, length(messages) - recent_keep)

    case summarize_messages(older_messages) do
      {:ok, summary} ->
        Logger.debug("Chat Summary: #{summary}")

        # Create a single summarized message entry
        summarized_entry = {:system, "Summary", summary, nil}
        [summarized_entry | recent_messages]

      {:error, reason} ->
        Logger.warning(
          "Failed to summarize messages: #{inspect(reason)}. Falling back to truncation."
        )

        # Fall back to keeping recent messages only
        recent_messages
    end
  end

  defp apply_summarization(messages, _threshold, _recent_keep), do: messages

  @doc false
  # Summarizes a list of messages using the LLM module
  @spec summarize_messages([{atom(), String.t(), String.t(), DateTime.t() | nil}]) ::
          {:ok, String.t()} | {:error, any()}
  defp summarize_messages(messages) do
    try do
      client = LLM.get_client()

      # Build the conversation text
      conversation_text =
        messages
        |> Enum.map(fn {role, username, content, _timestamp} ->
          role_label = if role == :assistant, do: "Bot", else: username
          "#{role_label}: #{content}"
        end)
        |> Enum.join("\n")

      # Use the LLM module's summarize_conversation function
      LLM.summarize_conversation(client, conversation_text)
    catch
      error ->
        Logger.error("Error during summarization: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc false
  # Counts the total number of tokens in all message content
  defp count_total_tokens(messages) do
    messages
    |> Enum.map(fn {_role, _username, content, _timestamp} -> content end)
    |> Enum.join(" ")
    |> Tokenizer.get_token_count()
  end
end
