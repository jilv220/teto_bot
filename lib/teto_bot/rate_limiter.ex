defmodule TetoBot.RateLimiter do
  @moduledoc """
  Rate limiter for controlling user request frequency using the Hammer library.

  Uses Hammer with ETS backend for fast, in-memory rate limiting.
  Each user has a separate counter that resets after the configured window period.

  - `allow?/1` - Check if a user can make a request

  ## Configuration

  Configure in your application config:

      config :teto_bot,
        rate_limit_window: 60,        # seconds
        rate_limit_max_requests: 5    # max requests per window

  ## Usage

      TetoBot.RateLimiter.allow?(user_id)
      #=> true | false

  """

  use Hammer, backend: :ets

  require Nostrum.Snowflake
  require Logger

  alias Nostrum.Snowflake
  alias TetoBot.RateLimiter

  # Client API

  @spec allow?(Snowflake.t()) :: boolean()
  @doc """
  Checks if a user is allowed to make a request based on rate limiting rules.

  ## Examples

      TetoBot.RateLimiter.allow?(123456789)
      #=> true

      # After multiple rapid requests...
      TetoBot.RateLimiter.allow?(123456789)
      #=> false

  """
  def allow?(user_id) when Snowflake.is_snowflake(user_id) do
    window = get_window_milliseconds()
    max_requests = get_max_requests()
    key = "user:#{user_id}"

    case RateLimiter.hit(key, window, max_requests) do
      {:allow, _count} ->
        Logger.debug("Allowing request for user #{user_id}")
        true

      {:deny, _retry_after} ->
        Logger.debug("Denying request for user #{user_id}")
        false
    end
  end

  # Guard against invalid user_id
  def allow?(_), do: false

  # Private functions

  defp get_window_milliseconds do
    seconds = Application.get_env(:teto_bot, :rate_limit_window, 60)
    # Convert to milliseconds for Hammer
    seconds * 1000
  end

  defp get_max_requests do
    Application.get_env(:teto_bot, :rate_limit_max_requests, 5)
  end
end
