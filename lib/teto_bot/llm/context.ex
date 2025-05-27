defmodule TetoBot.LLM.Context do
  require Logger

  @prompt_key "llm_sys_prompt"

  def get_system_prompt do
    case Redix.command(:redix, ["GET", @prompt_key]) do
      {:ok, nil} ->
        Logger.error("No system prompt found in Redis")
        {:error, :no_prompt_found}

      {:ok, prompt} ->
        {:ok, prompt}

      {:error, reason} ->
        Logger.error("Failed to fetch system prompt from Redis: #{inspect(reason)}")
        {:error, :redis_error}
    end
  end

  @spec update_system_prompt(any()) :: {:error, :invalid_prompt | :redis_error} | {:ok, binary()}
  def update_system_prompt(prompt) when is_binary(prompt) do
    case Redix.command(:redix, ["SET", @prompt_key, prompt]) do
      {:ok, "OK"} ->
        Logger.info("System prompt updated in Redis")
        {:ok, prompt}

      {:error, reason} ->
        Logger.error("Failed to update system prompt in Redis: #{inspect(reason)}")
        {:error, :redis_error}
    end
  end

  def update_system_prompt(_), do: {:error, :invalid_prompt}
end
