defmodule Mix.Tasks.NewPromptVersion do
  use Mix.Task
  alias TetoBot.LLM.PromptManager

  @shortdoc "Creates a new prompt version"

  @moduledoc """
  Creates a new prompt version file.

  ## Usage

      mix new_prompt_version 1.2.0           # Copy from latest version
      mix new_prompt_version 1.2.0 --from 1.1.0  # Copy from specific version
      mix new_prompt_version 1.2.0 --blank   # Create blank template

  ## Examples

      mix new_prompt_version 1.1.0
      mix new_prompt_version 2.0.0 --from 1.5.2
      mix new_prompt_version 1.2.0 --blank
  """

  def run(args) do
    Mix.Task.run("compile")

    {opts, parsed_args, _} =
      OptionParser.parse(args,
        switches: [from: :string, blank: :boolean],
        aliases: [f: :from, b: :blank]
      )

    if parsed_args == [] do
      Mix.shell().error("Version number is required")

      Mix.shell().info(
        "Usage: mix new_prompt_version <version> [--from <source_version>] [--blank]"
      )

      System.halt(1)
    end

    [version | _] = parsed_args

    unless valid_version?(version) do
      Mix.shell().error(
        "Invalid version format. Use semantic versioning: major.minor.patch (e.g., 1.2.3)"
      )

      System.halt(1)
    end

    create_new_version(version, opts)
  end

  defp create_new_version(version, opts) do
    filename = "v#{version}.md"
    file_path = Path.join([File.cwd!(), "priv", "prompts", filename])

    if File.exists?(file_path) do
      Mix.shell().error("Version v#{version} already exists")
      System.halt(1)
    end

    content = get_content(opts)

    case File.write(file_path, content) do
      :ok ->
        Mix.shell().info("Created new prompt version: v#{version}")
        Mix.shell().info("File: #{file_path}")
        Mix.shell().info("Edit the file and then run: mix update_prompt --version #{version}")

      {:error, reason} ->
        Mix.shell().error("Failed to create version file: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp get_content(opts) do
    cond do
      opts[:blank] ->
        """
        # Kasane Teto System Prompt - Version Template

        ## System

        You are a discord bot cosplaying as Kasane Teto...

        ## Core Personality Rules

        - Add your rules here...

        ## Language & Communication

        - Add communication guidelines...

        ## Response Guidelines

        - Add response formatting rules...

        ## Intimacy Tiers & Behavior

        - Define intimacy levels...

        ## Profile

        Add character profile information...

        ## Character Table

        Add character details in table format...
        """

      opts[:from] ->
        source_version = opts[:from]

        case PromptManager.read_version(source_version) do
          {:ok, content} ->
            content

          {:error, :file_not_found} ->
            Mix.shell().error("Source version v#{source_version} not found")
            System.halt(1)
        end

      true ->
        case PromptManager.read_latest() do
          {:ok, content} ->
            content

          {:error, :no_versions_found} ->
            Mix.shell().info("No existing versions found, creating blank template")
            get_content(blank: true)

          {:error, _} ->
            Mix.shell().error("Failed to read latest version")
            System.halt(1)
        end
    end
  end

  defp valid_version?(version) do
    Regex.match?(~r/^\d+\.\d+\.\d+$/, version)
  end
end
