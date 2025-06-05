defmodule TetoBot.LLM.PromptManager do
  @moduledoc """
  Manages versioned system prompts stored in priv/prompts/

  Expected file naming convention: v{major}.{minor}.{patch}.md
  Examples: v1.0.0.md, v1.2.3.md, v2.0.0.md
  """

  require Logger

  @prompts_dir "prompts"

  defp get_prompts_path do
    # Use a more reliable way to get the priv directory
    case :code.priv_dir(:teto_bot) do
      {:error, :bad_name} ->
        # Fallback for when the app isn't fully loaded
        Path.join([File.cwd!(), "priv", @prompts_dir])

      priv_dir ->
        Path.join([priv_dir, @prompts_dir])
    end
  end

  @doc """
  Lists all available prompt versions sorted by semantic version (latest first)
  """
  def list_versions do
    prompts_path = get_prompts_path()

    case File.ls(prompts_path) do
      {:ok, files} ->
        versions =
          files
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.filter(&valid_version_format?/1)
          |> Enum.map(&parse_version/1)
          |> Enum.sort(&version_compare/2)
          |> Enum.reverse()

        {:ok, versions}

      {:error, reason} ->
        Logger.error("Failed to list prompt versions: #{inspect(reason)}")
        {:error, :directory_not_found}
    end
  end

  @doc """
  Gets the latest version available
  """
  def get_latest_version do
    case list_versions() do
      {:ok, [latest | _]} -> {:ok, latest}
      {:ok, []} -> {:error, :no_versions_found}
      error -> error
    end
  end

  @doc """
  Reads the content of a specific version
  """
  def read_version(version) when is_binary(version) do
    filename = "v#{version}.md"
    file_path = Path.join([get_prompts_path(), filename])

    case File.read(file_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, reason} ->
        Logger.error("Failed to read version #{version} from #{file_path}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  @doc """
  Reads the latest version's content
  """
  def read_latest do
    case get_latest_version() do
      {:ok, version} -> read_version(version)
      error -> error
    end
  end

  @doc """
  Validates if a filename follows the version format v{major}.{minor}.{patch}.md
  """
  def valid_version_format?(filename) do
    case Regex.match?(~r/^v\d+\.\d+\.\d+\.md$/, filename) do
      true -> true
      false -> false
    end
  end

  # Private functions

  defp parse_version(filename) do
    filename
    |> String.replace_suffix(".md", "")
    |> String.replace_prefix("v", "")
  end

  defp version_compare(v1, v2) do
    [maj1, min1, patch1] = String.split(v1, ".") |> Enum.map(&String.to_integer/1)
    [maj2, min2, patch2] = String.split(v2, ".") |> Enum.map(&String.to_integer/1)

    cond do
      maj1 != maj2 -> maj1 < maj2
      min1 != min2 -> min1 < min2
      true -> patch1 < patch2
    end
  end
end
