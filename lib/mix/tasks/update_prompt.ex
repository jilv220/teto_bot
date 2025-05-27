defmodule Mix.Tasks.UpdatePrompt do
  use Mix.Task
  alias TetoBot.LLM

  @shortdoc "Updates the system prompt in Redis from priv/system_prompt.md"

  def run(_) do
    Mix.Task.run("app.start")

    prompt_path = Path.join(:code.priv_dir(:teto_bot), "system_prompt.md")

    case File.read(prompt_path) do
      {:ok, prompt} ->
        case LLM.Context.update_system_prompt(prompt) do
          {:ok, _} ->
            Mix.shell().info("System prompt updated successfully from #{prompt_path}")

          {:error, :redis_error} ->
            Mix.shell().error("Failed to update system prompt: Redis error")
            System.halt(1)

          {:error, :invalid_prompt} ->
            Mix.shell().error("Invalid prompt: Must be a string")
            System.halt(1)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to read #{prompt_path}: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
