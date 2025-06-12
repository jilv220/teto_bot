defmodule TetoBot.RateLimiting.ChannelLimiter do
  @moduledoc """
  Channel-based rate limiter using the Hammer library.

  Controls frequency of requests per channel using time-based sliding windows.
  Each channel has a separate counter that resets after the configured window period.

  ## Configuration

  Configure via the RateLimiting context:

      config :teto_bot, TetoBot.RateLimiting,
        rate_limit_window: 60,        # seconds
        rate_limit_max_requests: 5    # max requests per window

  ## Examples

      TetoBot.RateLimiting.ChannelLimiter.allow?(channel_id)
      #=> true | false

  """

  use Hammer, backend: :ets

  alias TetoBot.RateLimiting.Behaviour
  alias Nostrum.Snowflake

  # Default configuration
  @defaults [
    rate_limit_window: 60,
    rate_limit_max_requests: 5
  ]

  @spec allow?(Snowflake.t()) :: boolean()
  @doc """
  Checks if a channel is allowed to make a request based on rate limiting rules.

  Bypasses rate limits in development environment.

  ## Examples

      TetoBot.RateLimiting.ChannelLimiter.allow?(123456789)
      #=> true

      # After multiple rapid requests...
      TetoBot.RateLimiting.ChannelLimiter.allow?(123456789)
      #=> false

  """
  def allow?(channel_id) do
    if Behaviour.valid_snowflake?(channel_id) do
      if Behaviour.bypass_dev_limits?() do
        Behaviour.log_decision("channel", channel_id, true, %{reason: "dev_bypass"})
        true
      else
        check_rate_limit(channel_id)
      end
    else
      false
    end
  end

  # Private functions

  defp check_rate_limit(channel_id) do
    window_ms = get_window_milliseconds()
    max_requests = get_max_requests()
    key = "channel:#{channel_id}"

    case hit(key, window_ms, max_requests) do
      {:allow, count} ->
        Behaviour.log_decision("channel", channel_id, true, %{
          count: count,
          limit: max_requests,
          window_ms: window_ms
        })

        true

      {:deny, retry_after} ->
        Behaviour.log_decision("channel", channel_id, false, %{
          retry_after: retry_after,
          limit: max_requests,
          window_ms: window_ms
        })

        false
    end
  end

  defp get_window_milliseconds do
    seconds = Behaviour.get_config(:rate_limit_window, @defaults)
    # Convert to milliseconds for Hammer
    seconds * 1000
  end

  defp get_max_requests do
    Behaviour.get_config(:rate_limit_max_requests, @defaults)
  end
end
