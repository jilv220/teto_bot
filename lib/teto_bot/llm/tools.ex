defmodule TetoBot.LLM.Tools do
  @moduledoc """
  Handles tool calling for the LLM.
  """
  require Logger
  alias TetoBot.Lyrics

  @tools [
    %{
      type: "function",
      function: %{
        name: "get_lyrics",
        description: "Get lyrics for a song",
        parameters: %{
          type: "object",
          properties: %{
            song: %{type: "string", description: "The song title"},
            artist: %{type: "string", description: "The artist name"}
          },
          required: [:song, :artist]
        }
      }
    }
  ]

  @doc """
  Returns the tools configuration for the LLM.
  """
  def tools, do: @tools

  @doc """
  Executes a tool call and returns the result.
  """
  @spec execute_tool(String.t(), map()) :: {:ok, any()} | {:error, String.t()}

  def execute_tool("get_lyrics", %{"song" => song, "artist" => artist}) do
    case Lyrics.get_lyrics(song, artist) do
      {:ok, lyrics} ->
        {:ok, %{song: song, artist: artist, lyrics: lyrics}}

      {:error, :not_found} ->
        {:error, "No lyrics found for '#{song}' by #{artist}"}

      {:error, reason} ->
        {:error, "Failed to retrieve lyrics: #{reason}"}
    end
  end

  def execute_tool(tool_name, _params) do
    {:error, "Unknown tool: #{tool_name}"}
  end
end
