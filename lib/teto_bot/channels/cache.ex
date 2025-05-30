defmodule TetoBot.Channels.Cache do
  use GenServer
  @behaviour TetoBot.Channels.CacheBehaviour

  require Logger
  require Nostrum.Snowflake

  alias Nostrum.Snowflake

  @doc """
  Starts the channel cache GenServer.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  @spec exists?(Snowflake.t()) :: boolean()
  @doc """
  Checks if a channel exists in the cache. If present, it means it is whitelisted
  """
  def exists?(channel_id) when Snowflake.is_snowflake(channel_id) do
    case :ets.lookup(__MODULE__, channel_id) do
      [{^channel_id, ^channel_id}] -> true
      [] -> false
    end
  end

  @impl true
  @spec add(Snowflake.t()) :: :ok
  @doc """
  Adds a channel to the cache.
  """
  def add(channel_id) when Snowflake.is_snowflake(channel_id) do
    GenServer.cast(__MODULE__, {:add, channel_id})
  end

  @impl true
  @spec remove(Snowflake.t()) :: :ok
  @doc """
  Removes a channel from the cache.
  """
  def remove(channel_id) when Snowflake.is_snowflake(channel_id) do
    GenServer.cast(__MODULE__, {:remove, channel_id})
  end

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:named_table, :set, :protected, read_concurrency: true])
    Logger.info(":ets table initialized")
    {:ok, table}
  end

  @impl true
  def handle_cast({:add, channel_id}, table) do
    :ets.insert(table, {channel_id, channel_id})
    {:noreply, table}
  end

  @impl true
  def handle_cast({:remove, channel_id}, table_id) do
    :ets.delete(table_id, channel_id)
    {:noreply, table_id}
  end
end
