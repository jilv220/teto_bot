defmodule TetoBot.MessageContext do
  @moduledoc """
  A GenServer managing a short-lived message context using an ETS table.

  Stores messages for each user within a configurable time window.
  Configuration keys under `:teto_bot`:
    - `:context_window`: Time window in seconds for storing messages (default: 300)
  """

  use GenServer
  require Logger

  @doc """
  Starts the MessageContext GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Stores a new message for a user with the current timestamp.
  """
  @spec store_message(integer(), String.t()) :: :ok
  def store_message(user_id, content) do
    GenServer.call(__MODULE__, {:store, user_id, content})
  end

  @doc """
  Retrieves the conversation context for a user within the time window.
  Returns a list of message contents in chronological order.
  """
  @spec get_context(integer()) :: [String.t()]
  def get_context(user_id) do
    window = Application.get_env(:teto_bot, :context_window, 300)
    now = System.monotonic_time(:second)

    :ets.match_object(:message_context, {user_id, :_, :_})
    |> Enum.filter(fn {_, timestamp, _} -> now - timestamp <= window end)
    |> Enum.sort_by(fn {_, timestamp, _} -> timestamp end)
    |> Enum.map(fn {_, _, content} -> content end)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(:message_context, [:bag, :public, :named_table])

    if table != nil do
      Logger.info("Initialized :message_context ETS table")
    end

    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:store, user_id, content}, _from, state) do
    now = System.monotonic_time(:second)
    :ets.insert(:message_context, {user_id, System.monotonic_time(:second), content})
    Logger.debug("Storing message for user #{user_id}: #{content} at #{now}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    window = Application.get_env(:teto_bot, :context_window, 300)
    now = System.monotonic_time(:second)

    :ets.select_delete(:message_context, [
      {{:_, :"$1", :_}, [{:>, {:-, now, :"$1"}, window}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    # Run cleanup every minute
    Process.send_after(self(), :cleanup, 60_000)
  end
end
