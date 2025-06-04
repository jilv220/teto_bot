defmodule TetoBot.LLM.Config do
  @moduledoc """
  Configuration management for LLM functionality.
  """

  @default_config %{
    llm_model_name: "grok-3-mini",
    llm_vision_model_name: "grok-2-vision-latest",
    llm_max_words: 50,
    llm_temperature: 0.7,
    llm_top_p: 0.9,
    llm_top_k: 40,
    llm_vision_temperature: 0.01
  }

  def get(key), do: Application.get_env(:teto_bot, key, @default_config[key])

  def get_all do
    Enum.into(@default_config, %{}, fn {key, default} ->
      {key, Application.get_env(:teto_bot, key, default)}
    end)
  end
end
