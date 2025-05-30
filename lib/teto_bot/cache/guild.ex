defmodule TetoBot.Cache.Guild do
  require Logger

  @guild_key "guild"

  def ids do
    case Redix.command(:redix, ["SMEMBERS", @guild_key]) do
      {:ok, guild_ids} -> {:ok, guild_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  def exists?(guild_id) do
    case Redix.command(:redix, ["SISMEMBER", @guild_key, guild_id]) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  def add_id(guild_id) do
    case Redix.command(:redix, ["SADD", @guild_key, guild_id]) do
      {:ok, _count} ->
        Logger.info("Guild #{guild_id} added")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def add_ids(guild_ids) when is_list(guild_ids) do
    # Add multiple guild_ids to the "active_guilds" set
    # The SADD command can take multiple members after the key.
    command = ["SADD", @guild_key] ++ guild_ids

    case Redix.command(:redix, command) do
      {:ok, count} ->
        Logger.info("[#{count} guilds added")
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def remove_id(guild_id) do
    case Redix.command(:redix, ["SREM", @guild_key, guild_id]) do
      {:ok, _count} ->
        Logger.info("Guild #{guild_id} removed")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
