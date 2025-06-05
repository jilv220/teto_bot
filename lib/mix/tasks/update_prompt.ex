defmodule Mix.Tasks.UpdatePrompt do
  use Mix.Task
  alias TetoBot.LLM
  alias TetoBot.LLM.PromptManager

  @shortdoc "Updates the system prompt in Redis from versioned prompts"

  @moduledoc """
  Updates the system prompt in Redis from versioned prompt files.

  ## Usage

      mix update_prompt                 # Uses the latest version
      mix update_prompt --version 1.0.0 # Uses specific version
      mix update_prompt --list          # Lists all available versions

  ## Examples

      mix update_prompt
      mix update_prompt --version 1.2.3
      mix update_prompt --list
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [version: :string, list: :boolean],
        aliases: [v: :version, l: :list]
      )

    cond do
      opts[:list] ->
        list_versions()

      opts[:version] ->
        Mix.Task.run("app.start")
        update_specific_version(opts[:version])

      true ->
        Mix.Task.run("app.start")
        update_latest_version()
    end
  end

  defp list_versions do
    case PromptManager.list_versions() do
      {:ok, versions} ->
        if Enum.empty?(versions) do
          Mix.shell().info("No prompt versions found in priv/prompts/")
        else
          Mix.shell().info("Available prompt versions:")

          versions
          |> Enum.with_index(1)
          |> Enum.each(fn {version, index} ->
            marker = if index == 1, do: " (latest)", else: ""
            Mix.shell().info("  v#{version}#{marker}")
          end)
        end

      {:error, :directory_not_found} ->
        Mix.shell().error("Prompts directory not found: priv/prompts/")

        Mix.shell().info(
          "Make sure you have prompt files in priv/prompts/ with naming format: v{major}.{minor}.{patch}.md"
        )

        System.halt(1)
    end
  end

  defp update_latest_version do
    case PromptManager.get_latest_version() do
      {:ok, version} ->
        Mix.shell().info("Using latest version: v#{version}")

        case PromptManager.read_version(version) do
          {:ok, prompt} ->
            update_prompt_in_redis(prompt, "v#{version}")

          {:error, :file_not_found} ->
            Mix.shell().error("Failed to read version v#{version}")
            System.halt(1)
        end

      {:error, :no_versions_found} ->
        Mix.shell().error("No prompt versions found in priv/prompts/")
        Mix.shell().info("Create a prompt file with format: v{major}.{minor}.{patch}.md")
        System.halt(1)

      {:error, :directory_not_found} ->
        Mix.shell().error("Prompts directory not found: priv/prompts/")
        System.halt(1)
    end
  end

  defp update_specific_version(version) do
    # Normalize version format (add 'v' prefix if missing)
    normalized_version =
      if String.starts_with?(version, "v"), do: String.trim_leading(version, "v"), else: version

    case PromptManager.read_version(normalized_version) do
      {:ok, prompt} ->
        update_prompt_in_redis(prompt, "v#{normalized_version}")

      {:error, :file_not_found} ->
        Mix.shell().error("Version v#{normalized_version} not found")
        Mix.shell().info("Available versions:")

        case PromptManager.list_versions() do
          {:ok, versions} ->
            Enum.each(versions, fn v -> Mix.shell().info("  v#{v}") end)

          _ ->
            Mix.shell().info("  None found")
        end

        System.halt(1)
    end
  end

  defp update_prompt_in_redis(prompt, version_label) do
    case LLM.Context.update_system_prompt(prompt) do
      {:ok, _} ->
        Mix.shell().info("System prompt updated successfully to #{version_label}")

      {:error, :redis_error} ->
        Mix.shell().error("Failed to update system prompt: Redis error")
        System.halt(1)

      {:error, :invalid_prompt} ->
        Mix.shell().error("Invalid prompt: Must be a string")
        System.halt(1)
    end
  end
end
