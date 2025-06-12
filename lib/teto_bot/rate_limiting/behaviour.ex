defmodule TetoBot.RateLimiting.Behaviour do
  @moduledoc """
  Shared behavior and utilities for rate limiting implementations.

  Provides common patterns like:
  - Configuration loading
  - Development environment bypassing
  - Logging utilities
  - Input validation

  """

  require Logger
  require Nostrum.Snowflake

  @doc """
  Checks if development environment should bypass rate limits.
  """
  @spec bypass_dev_limits?() :: boolean()
  def bypass_dev_limits? do
    Application.get_env(:teto_bot, :env) == :dev
  end

  @doc """
  Logs rate limit decision with consistent format.
  """
  @spec log_decision(String.t(), term(), boolean(), map()) :: :ok
  def log_decision(limiter_type, identifier, allowed?, metadata \\ %{}) do
    action = if allowed?, do: "Allowing", else: "Denying"

    base_message = "#{action} #{limiter_type} request for #{identifier}"

    full_message =
      if map_size(metadata) > 0 do
        metadata_str =
          metadata
          |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
          |> Enum.join(", ")

        "#{base_message} (#{metadata_str})"
      else
        base_message
      end

    Logger.debug(full_message)
  end

  @doc """
  Validates that the given value is a valid Snowflake ID.
  """
  @spec valid_snowflake?(term()) :: boolean()
  def valid_snowflake?(value) do
    Nostrum.Snowflake.is_snowflake(value)
  end

  @doc """
  Gets application configuration with fallback defaults.
  """
  @spec get_config(atom(), keyword()) :: term()
  def get_config(key, defaults \\ []) do
    config = Application.get_env(:teto_bot, TetoBot.RateLimiting, [])

    defaults
    |> Keyword.merge(config)
    |> Keyword.get(key)
  end

  @doc """
  Common error responses for invalid inputs.
  """
  @spec invalid_input_error(String.t()) :: {:error, atom()}
  def invalid_input_error("channel"), do: {:error, :invalid_channel_id}
  def invalid_input_error("user"), do: {:error, :invalid_user_id}
  def invalid_input_error(_), do: {:error, :invalid_input}

  @doc """
  Wraps a rate limiting decision with consistent error handling.
  """
  @spec handle_rate_limit_check(term(), String.t(), (-> term())) :: term()
  def handle_rate_limit_check(identifier, type, check_fn) do
    if valid_snowflake?(identifier) do
      try do
        check_fn.()
      rescue
        exception ->
          Logger.error("Rate limit check failed for #{type} #{identifier}: #{inspect(exception)}")
          invalid_input_error(type)
      end
    else
      invalid_input_error(type)
    end
  end
end
