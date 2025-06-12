defmodule TetoBot.RateLimiting do
  @moduledoc """
  Rate limiting domain for controlling request frequency across different scopes.

  This context manages rate limiting for both channel-based and user-based restrictions,
  providing a unified interface for rate limiting operations throughout the application.

  ## Channel Rate Limiting
  Controls frequency of requests per channel using time-based windows.

  ## User Rate Limiting
  Controls daily message limits based on user voting status and subscription tiers.

  ## Configuration

      config :teto_bot, TetoBot.RateLimiting,
        # Channel rate limiting (using Hammer)
        rate_limit_window: 60,        # seconds
        rate_limit_max_requests: 5,   # max requests per window

        # User daily limits
        free_user_daily_limit: 10,
        voted_user_daily_limit: 30

  ## Usage

      # Channel rate limiting
      TetoBot.RateLimiting.allow_channel?(channel_id)
      #=> true | false

      # User rate limiting
      TetoBot.RateLimiting.allow_user?(user_id)
      #=> {:ok, true} | {:ok, false} | {:error, reason}

  """

  alias TetoBot.RateLimiting.{ChannelLimiter, UserLimiter}

  # Public API - Channel Rate Limiting

  @doc """
  Checks if a channel is allowed to make a request.
  """
  defdelegate allow_channel?(channel_id), to: ChannelLimiter, as: :allow?

  # Public API - User Rate Limiting

  @doc """
  Checks if a user is allowed to send a message.
  """
  defdelegate allow_user?(user_id), to: UserLimiter, as: :allow?

  @doc """
  Records when a user votes for the bot.
  """
  defdelegate record_vote(user_id), to: UserLimiter

  @doc """
  Gets a user's current rate limit status.
  """
  defdelegate get_user_status(user_id), to: UserLimiter

  @doc """
  Returns the current configuration for user rate limiting.
  """
  defdelegate get_user_config(), to: UserLimiter, as: :get_config
end
