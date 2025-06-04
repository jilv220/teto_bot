defmodule TetoBot.Lyrics do
  @moduledoc """
  Handles storage and retrieval of lyrics in Redis.
  """
  require Logger

  @lyrics_prefix "lyrics:"

  @doc """
  Stores lyrics for a song in Redis.
  
  ## Parameters
    - song: The song title
    - artist: The artist name
    - lyrics: The lyrics text
  """
  @spec store_lyrics(String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def store_lyrics(song, artist, lyrics) do
    key = "#{@lyrics_prefix}#{normalize_key(artist)}:#{normalize_key(song)}"
    
    case Redix.command(:redix, ["SET", key, lyrics]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> 
        Logger.error("Failed to store lyrics: #{inspect(reason)}")
        {:error, "Failed to store lyrics"}
    end
  end

  @doc """
  Retrieves lyrics for a song from Redis.
  
  ## Parameters
    - song: The song title
    - artist: The artist name
  """
  @spec get_lyrics(String.t(), String.t()) :: {:ok, String.t()} | {:error, :not_found | String.t()}
  def get_lyrics(song, artist) do
    key = "#{@lyrics_prefix}#{normalize_key(artist)}:#{normalize_key(song)}"
    
    case Redix.command(:redix, ["GET", key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, lyrics} -> {:ok, lyrics}
      {:error, reason} -> 
        Logger.error("Failed to retrieve lyrics: #{inspect(reason)}")
        {:error, "Failed to retrieve lyrics"}
    end
  end

  @doc """
  Lists all stored lyrics in Redis.
  """
  @spec list_lyrics() :: {:ok, [map()]} | {:error, String.t()}
  def list_lyrics do
    case Redix.command(:redix, ["KEYS", "#{@lyrics_prefix}*"]) do
      {:ok, keys} when is_list(keys) ->
        keys
        |> Enum.map(fn key ->
          [artist, song] = 
            key
            |> String.replace_leading(@lyrics_prefix, "")
            |> String.split(":", parts: 2)
            
          %{
            artist: URI.decode(artist),
            song: URI.decode(song)
          }
        end)
        |> then(&{:ok, &1})
        
      {:error, reason} ->
        Logger.error("Failed to list lyrics: #{inspect(reason)}")
        {:error, "Failed to list lyrics"}
    end
  end

  defp normalize_key(string) do
    string
    |> String.downcase()
    |> String.replace(" ", "_")
    |> URI.encode()
  end
end
