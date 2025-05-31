defmodule TetoBot.MessageContext do
  @moduledoc """
  A module for retrieving channel-wide message context using Nostrum's MessageCache.

  Fetches messages for a channel within a configurable time window and formats them
  with roles (:user or :assistant). Relies entirely on Nostrum's MessageCache for
  message storage.

  Configuration keys under `:teto_bot`:
    - `:context_window`: Time window in seconds for retrieving messages (default: 300)
  """

  require Logger
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct.Message
  alias Nostrum.Bot

  @doc """
  Retrieves the conversation context for a channel within the time window.
  Returns a list of {role, content} tuples in chronological order.
  """
  @spec get_context(integer()) :: [{:user | :assistant, String.t()}]
  def get_context(channel_id) do
    window = Application.get_env(:teto_bot, :context_window, 300)
    after_timestamp = DateTime.utc_now() |> DateTime.add(-window, :second)

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
    |> Enum.map(fn {role, username, content, _} -> {role, username, content} end)
  end
end
