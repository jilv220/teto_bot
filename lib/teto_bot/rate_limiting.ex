defmodule TetoBot.RateLimiting do
  @moduledoc """
  Rate limiting domain for controlling request frequency across different scopes.

  This context manages rate limiting for both channel-based and user-based restrictions,
  providing a unified interface for rate limiting operations throughout the application.

  ## Channel Rate Limiting
  Controls frequency of requests per channel using time-based windows.

  ## User Rate Limiting
  Controls message access using a credit-based refill system.
  - All users start with daily credit refill cap amount
  - Credits refill to daily cap at midnight UTC if below cap
  - Voting status checked dynamically via TopggEx API
  - Credits can accumulate but are capped at daily refill

  ## Configuration

      config :teto_bot, TetoBot.RateLimiting,
        # Channel rate limiting (using Hammer)
        rate_limit_window: 60,        # seconds
        rate_limit_max_requests: 5,   # max requests per window

        # User credit system
        daily_credit_refill_cap: 30,  # credits refilled to this cap daily
        vote_credit_bonus: 30         # credits added per vote

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
  Checks if a user has message credits and deducts one if available.
  """
  defdelegate allow_user?(user_id), to: UserLimiter, as: :allow?

  @doc """
  Gets a user's current message credits and voting status.
  """
  defdelegate get_user_status(user_id), to: UserLimiter

  @doc """
  Adds vote bonus credits to a user when they vote (called from webhook).
  """
  defdelegate add_vote_credits(user_id), to: UserLimiter

  @doc """
  Returns the current configuration for the credit system.
  """
  defdelegate get_user_config(), to: UserLimiter, as: :get_config
  def get_vote_credit_bonus(), do: get_user_config().vote_credit_bonus
  def get_daily_credit_refill_cap(), do: get_user_config().daily_credit_refill_cap
end
