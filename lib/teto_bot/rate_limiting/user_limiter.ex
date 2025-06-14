defmodule TetoBot.RateLimiting.UserLimiter do
  @moduledoc """
  User-specific rate limiter using a message credits refill system.

  Features:
  - All users start with daily credit refill cap amount
  - Credits refill to daily cap at midnight UTC if below cap
  - Voting adds vote bonus credits immediately
  - Credits can accumulate but are capped at daily refill
  - Voting status tracked internally (12-hour cooldown)
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
      #=> {:ok, %{message_credits: 25, has_voted: true}}

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
             has_voted: boolean()
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

  @spec get_user_status(Snowflake.t()) :: status_result() | {:error, term()}
  @doc """
  Gets a user's current message credits and voting status.

  Returns comprehensive status information including credits and voting status.
  Voting status is determined by checking if the user has voted within the last 12 hours
  (TopGG's voting cooldown period).

  ## Examples

      TetoBot.RateLimiting.UserLimiter.get_user_status(123456789)
      #=> {:ok, %{message_credits: 25, has_voted: true}}

  """
  def get_user_status(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_get_user_status(user_id)
    else
      Behaviour.invalid_input_error("user")
    end
  end

  @spec add_vote_credits(Snowflake.t()) :: :ok | {:error, term()}
  @doc """
  Adds vote bonus credits to a user when they vote.

  Called from the TopGG webhook when a vote is received.

  ## Examples

      TetoBot.RateLimiting.UserLimiter.add_vote_credits(123456789)
      #=> :ok

  """
  def add_vote_credits(user_id) do
    if Behaviour.valid_snowflake?(user_id) do
      do_add_vote_credits(user_id)
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

  defp do_get_user_status(user_id) do
    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_data_with_vote_info(user) do
      has_voted = check_user_vote_status(loaded_user)

      status = %{
        message_credits: loaded_user.message_credits || 0,
        has_voted: has_voted
      }

      {:ok, status}
    end
  end

  defp check_user_vote_status(user) do
    case user.last_voted_at do
      nil ->
        false

      last_voted_at ->
        # TopGG voting cooldown is 12 hours
        twelve_hours_ago = DateTime.add(DateTime.utc_now(), -12, :hour)
        DateTime.compare(last_voted_at, twelve_hours_ago) == :gt
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

  defp load_user_data_with_vote_info(user) do
    case Ash.load(user, [:message_credits, :last_voted_at]) do
      {:ok, loaded_user} ->
        {:ok, loaded_user}

      {:error, reason} ->
        Logger.error("Failed to load user data with vote info: #{inspect(reason)}")
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

  defp update_user_vote_and_credits(user, new_credits) do
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

  defp do_add_vote_credits(user_id) do
    vote_bonus = Behaviour.get_config(:vote_credit_bonus, @defaults)

    with {:ok, user} <- get_or_create_user(user_id),
         {:ok, loaded_user} <- load_user_data(user) do
      current_credits = loaded_user.message_credits || 0
      new_credits = current_credits + vote_bonus

      case update_user_vote_and_credits(loaded_user, new_credits) do
        {:ok, _} ->
          Logger.info(
            "Added #{vote_bonus} vote credits to user #{user_id} (total: #{new_credits})"
          )

          :ok

        {:error, reason} ->
          Logger.error("Failed to add vote credits for user #{user_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
