defmodule TetoBot.RateLimiting.UserLimiter do
  @moduledoc """
  User-specific rate limiter using a message credits refill system.

  Features:
  - All users start with daily credit refill cap amount
  - Credits refill to daily cap at midnight UTC if below cap
  - Voting adds vote bonus credits immediately
  - Credits can accumulate but are capped at daily refill
  - Development environment bypass

  ## Configuration

  Configure via the RateLimiting context:

      config :teto_bot, TetoBot.RateLimiting,
        daily_credit_refill_cap: 30,
        vote_credit_bonus: 30

  ## Examples

      TetoBot.RateLimiting.UserLimiter.allow?(user_id)
      #=> {:ok, true} | {:ok, false} | {:error, reason}

      TetoBot.RateLimiting.UserLimiter.get_user_status(user_id)
      #=> {:ok, %{message_credits: 25, has_voted_today: true}}

  """

  require Logger
  require Ash.Query

  alias TetoBot.RateLimiting.Behaviour
  alias TetoBot.Accounts
  alias Nostrum.Snowflake

  # Default configuration
  @defaults [
    vote_credit_bonus: 30,
    daily_credit_refill_cap: 30
  ]

  @type status_result ::
          {:ok,
           %{
             message_credits: non_neg_integer(),
             has_voted_today: boolean(),
             is_voted_user: boolean()
           }}

  # Client API

  @spec allow?(Snowflake.t()) :: {:ok, boolean()} | {:error, term()}
  @doc """
  Checks if a user has message credits available and deducts one credit if they do.

  Bypasses rate limits in development environment.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.allow?(123456789)
      #=> {:ok, true}

      # After running out of credits...
      TetoBot.RateLimiting.UserLimiter.allow?(123456789)
      #=> {:ok, false}

  """
  def allow?(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      if Behaviour.bypass_dev_limits?() do
        Behaviour.log_decision("user", user_id, true, %{reason: "dev_bypass"})
        {:ok, true}
      else
        check_and_deduct_credit(user_id)
      end
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec record_vote(Snowflake.t()) :: :ok | {:error, term()}
  @doc """
  Records when a user votes for the bot and adds credit bonus.

  Updates the user's last_voted_at timestamp and adds vote credit bonus.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.record_vote(123456789)
      #=> :ok

  """
  def record_vote(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_record_vote(user_id)
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec get_user_status(Snowflake.t()) :: status_result() | {:error, term()}
  @doc """
  Gets a user's current message credits and voting status.

  Returns comprehensive status information including credits and voting status.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.get_user_status(123456789)
      #=> {:ok, %{message_credits: 25, has_voted_today: true, is_voted_user: true}}

  """
  def get_user_status(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_get_user_status(user_id)
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec get_config() :: %{
          vote_credit_bonus: non_neg_integer(),
          daily_credit_refill_cap: non_neg_integer()
        }
  @doc """
  Returns the current configuration for the credit system.
  """
  def get_config do
    %{
      vote_credit_bonus: Behaviour.get_config(:vote_credit_bonus, @defaults),
      daily_credit_refill_cap: Behaviour.get_config(:daily_credit_refill_cap, @defaults)
    }
  end

  # Private functions

  defp check_and_deduct_credit(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_data(user) do
      credits = loaded_user.message_credits || 0
      allowed? = credits > 0

      if allowed? do
        case update_user_credits(loaded_user, credits - 1) do
          {:ok, _} ->
            Behaviour.log_decision("user", user_id, true, %{
              credits_remaining: credits - 1,
              credits_used: 1
            })

            {:ok, true}

          {:error, reason} ->
            Logger.error("Failed to deduct credit for user #{user_id}: #{inspect(reason)}")
            {:error, reason}
        end
      else
        Behaviour.log_decision("user", user_id, false, %{
          credits_remaining: 0,
          reason: "no_credits"
        })

        {:ok, false}
      end
    end
  end

  defp do_record_vote(user_id) do
    vote_bonus = Behaviour.get_config(:vote_credit_bonus, @defaults)

    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_data(user),
         {:ok, _updated_user} <- update_user_vote_and_credits(loaded_user, vote_bonus) do
      Logger.info("Recorded vote for user #{user_id} and added #{vote_bonus} credits")
      :ok
    end
  end

  defp do_get_user_status(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_status_data(user) do
      status = %{
        message_credits: loaded_user.message_credits || 0,
        has_voted_today: loaded_user.has_voted_today,
        is_voted_user: loaded_user.is_voted_user
      }

      {:ok, status}
    end
  end

  defp get_or_create_user(user_id) do
    case Accounts.get_user(user_id) do
      {:ok, nil} ->
        Accounts.create_user(user_id)

      {:ok, user} ->
        {:ok, user}

      {:error, reason} ->
        Logger.error("Failed to get user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_user_data(user) do
    case Ash.load(user, [:message_credits]) do
      {:ok, loaded_user} ->
        {:ok, loaded_user}

      {:error, reason} ->
        Logger.error("Failed to load user data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_user_status_data(user) do
    case Ash.load(user, [:message_credits, :is_voted_user, :has_voted_today]) do
      {:ok, loaded_user} ->
        {:ok, loaded_user}

      {:error, reason} ->
        Logger.error("Failed to load user status data: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_user_credits(user, new_credits) do
    case user
         |> Ash.Changeset.for_update(:update, %{message_credits: new_credits})
         |> Ash.update() do
      {:ok, updated_user} ->
        {:ok, updated_user}

      {:error, reason} ->
        Logger.error("Failed to update user credits: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_user_vote_and_credits(user, credit_bonus) do
    current_credits = user.message_credits || 0
    new_credits = current_credits + credit_bonus

    case user
         |> Ash.Changeset.for_update(:update, %{
           last_voted_at: DateTime.utc_now(),
           message_credits: new_credits
         })
         |> Ash.update() do
      {:ok, updated_user} ->
        {:ok, updated_user}

      {:error, reason} ->
        Logger.error("Failed to update user vote and credits: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
