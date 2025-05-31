defmodule TetoBot.Cache.Snowflake do
  @moduledoc """
  A generic ETS-based cache for Discord snowflakes.

  This module provides a reusable pattern for caching Discord IDs (channels, guilds, users, etc.)
  with a simple exists?/add/remove interface.
  """

  defmacro __using__(opts) do
    entity_type = Keyword.get(opts, :entity_type, "entity")

    quote do
      use GenServer

      require Logger
      require Nostrum.Snowflake

      alias Nostrum.Snowflake
      @table_name __MODULE__
      @entity_type unquote(entity_type)

      @doc """
      Starts the #{@entity_type} cache GenServer.
      """
      def start_link(_opts) do
        GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
      end

      @spec exists?(Snowflake.t()) :: boolean()
      @doc """
      Checks if a #{@entity_type} exists in the cache. If present, it means it is whitelisted.
      """
      def exists?(id) when Snowflake.is_snowflake(id) do
        case :ets.lookup(@table_name, id) do
          [{^id, ^id}] -> true
          [] -> false
        end
      end

      @spec add(Snowflake.t()) :: :ok
      @doc """
      Adds a #{@entity_type} to the cache.
      """
      def add(id) when Snowflake.is_snowflake(id) do
        GenServer.cast(__MODULE__, {:add, id})
      end

      @spec remove(Snowflake.t()) :: :ok
      @doc """
      Removes a #{@entity_type} from the cache.
      """
      def remove(id) when Snowflake.is_snowflake(id) do
        GenServer.cast(__MODULE__, {:remove, id})
      end

      @spec list() :: [Snowflake.t()]
      @doc """
      Lists all #{@entity_type}s in the cache.
      """
      def list() do
        GenServer.call(__MODULE__, :list)
      end

      @spec clear() :: :ok
      @doc """
      Clears all #{@entity_type}s from the cache.
      """
      def clear() do
        GenServer.cast(__MODULE__, :clear)
      end

      @spec count() :: non_neg_integer()
      @doc """
      Returns the number of #{@entity_type}s in the cache.
      """
      def count() do
        GenServer.call(__MODULE__, :count)
      end

      # GenServer Callbacks
      @impl true
      def init(_opts) do
        table = :ets.new(@table_name, [:named_table, :set, :protected, read_concurrency: true])

        Logger.info("#{@entity_type |> String.capitalize()} ETS cache initialized")

        {:ok, table}
      end

      @impl true
      def handle_cast({:add, id}, table) do
        :ets.insert(table, {id, id})
        Logger.debug("Added #{@entity_type} #{id} to cache")
        {:noreply, table}
      end

      @impl true
      def handle_cast({:remove, id}, table) do
        :ets.delete(table, id)
        Logger.debug("Removed #{@entity_type} #{id} from cache")
        {:noreply, table}
      end

      @impl true
      def handle_cast(:clear, table) do
        :ets.delete_all_objects(table)
        Logger.info("Cleared all #{@entity_type}s from cache")
        {:noreply, table}
      end

      @impl true
      def handle_call(:list, _from, table) do
        ids = :ets.tab2list(table) |> Enum.map(fn {id, _} -> id end)
        {:reply, ids, table}
      end

      @impl true
      def handle_call(:count, _from, table) do
        count = :ets.info(table, :size)
        {:reply, count, table}
      end
    end
  end
end
