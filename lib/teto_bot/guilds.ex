defmodule TetoBot.Guilds do
  require Nostrum.Snowflake
  require Logger

  import Ecto.Query

  alias TetoBot.Users.UserGuild
  alias Nostrum.Snowflake
  alias TetoBot.Guilds.Guild
  alias TetoBot.Guilds.Cache

  @repo Application.compile_env(:teto_bot, :repo, TetoBot.Repo)

  @spec guild_create(Snowflake.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()} | {:error, :invalid_id}
  @doc """
  A guild added our app
  Insert a new guild record `guilds` table and add to cache
  """
  def guild_create(guild_id) when Snowflake.is_snowflake(guild_id) do
    case %Guild{}
         |> Guild.changeset(%{guild_id: guild_id})
         |> @repo.insert([]) do
      {:ok, _guild} = result ->
        Cache.add(guild_id)
        result

      error ->
        error
    end
  end

  def guild_create(_), do: {:error, :invalid_id}

  @spec guild_delete(Snowflake.t()) ::
          {:ok, Ecto.Schema.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :not_found}
          | {:error, :invalid_id}
  @doc """
  A guild removed our app
  Remove the record from `guilds` table and cache
  """
  def guild_delete(guild_id) when Snowflake.is_snowflake(guild_id) do
    case @repo.get_by(Guild, [guild_id: guild_id], []) do
      nil ->
        {:error, :not_found}

      guild ->
        case @repo.delete(guild, []) do
          {:ok, _guild} = result ->
            Cache.remove(guild_id)
            result

          error ->
            error
        end
    end
  end

  def guild_delete(_), do: {:error, :invalid_id}

  @doc """
  Check if guild is a member (first check cache, then database if not found)
  """
  def member?(guild_id) when Snowflake.is_snowflake(guild_id) do
    # Fast cache lookup first
    if Cache.exists?(guild_id) do
      true
    else
      # Fallback to database lookup
      case @repo.get_by(Guild, [guild_id: guild_id], []) do
        nil ->
          false

        _guild ->
          # Add to cache for future fast lookups
          Cache.add(guild_id)
          true
      end
    end
  end

  def member?(_), do: false

  @spec members(Snowflake.t()) :: {:ok, [Snowflake.t()]} | {:error, any()}
  @doc """
  Get all member user IDs from a specific guild
  Returns a list of user IDs (Snowflakes) that are members of the guild

  ## Examples
      iex> TetoBot.Guilds.members(12345)
      {:ok, [67890, 11111, 22222]}

      iex> TetoBot.Guilds.members(99999)
      {:ok, []}

      iex> TetoBot.Guilds.members("invalid")
      {:error, :invalid_id}
  """
  def members(guild_id) when Snowflake.is_snowflake(guild_id) do
    try do
      result =
        from(ug in UserGuild,
          where: ug.guild_id == ^guild_id,
          select: ug.user_id,
          order_by: ug.user_id
        )
        |> @repo.all([])

      {:ok, result}
    rescue
      error in Ecto.QueryError ->
        Logger.error("Failed to get members: #{inspect(error)}")
        {:error, error}
    end
  end

  def members(_), do: {:error, :invalid_id}

  @spec ids() :: [Snowflake.t()]
  @doc """
  Get all guild IDs from the database
  Returns a list of guild IDs (Snowflakes)
  """
  def ids do
    @repo.all(Guild, [])
    |> Enum.map(& &1.guild_id)
  end

  @doc """
  Get cache statistics
  """
  def cache_stats() do
    %{
      cached_guilds: Cache.count(),
      cached_guild_ids: Cache.list()
    }
  end

  @doc """
  Load all guild IDs from database into cache
  Useful for cache warming on application startup
  """
  def warm_cache do
    ids()
    |> Enum.each(&Cache.add/1)
  end
end
