defmodule TetoBot.Accounts.DecayWorker do
  @moduledoc """
  An Oban worker responsible for periodically decaying intimacy scores for users
  who have been inactive for a configured duration.

  This worker is typically scheduled to run at regular intervals (e.g., every 12 hours)
  using Oban's cron functionality, configured in `config/config.exs`.

  Upon execution, it loads its operational parameters (such as inactivity threshold,
  decay amount, and minimum intimacy score) from the application environment under
  the key `{:teto_bot, TetoBot.Accounts.Decay}`. The core decay logic is then
  delegated to `TetoBot.Accounts.Decay.perform_decay_check_logic/1`.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias TetoBot.Accounts.Decay

  # Default configuration
  @default_inactivity_threshold :timer.hours(24 * 3)
  @default_decay_amount 5
  @default_minimum_intimacy 5

  @impl Oban.Worker
  def perform(_job) do
    case load_config() do
      {:ok, config} ->
        Logger.info("DecayWorker: Starting intimacy decay check with config: #{inspect(config)}")
        Decay.perform_decay_check_logic(config)
        Logger.info("DecayWorker: Intimacy decay check performed.")
        :ok

      {:error, reason} ->
        Logger.error("DecayWorker: Halting due to invalid configuration. Reason: #{reason}")
        {:error, reason}
    end
  end

  def trigger do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp load_config do
    app_config = Application.get_env(:teto_bot, Decay, [])

    inactivity_threshold =
      Keyword.get(app_config, :inactivity_threshold, @default_inactivity_threshold)

    decay_amount = Keyword.get(app_config, :decay_amount, @default_decay_amount)
    minimum_intimacy = Keyword.get(app_config, :minimum_intimacy, @default_minimum_intimacy)

    with :ok <-
           Decay.validate_positive_integer(
             inactivity_threshold,
             :inactivity_threshold
           ),
         :ok <- Decay.validate_positive_integer(decay_amount, :decay_amount),
         :ok <-
           Decay.validate_positive_integer(minimum_intimacy, :minimum_intimacy) do
      config_map = %{
        inactivity_threshold: inactivity_threshold,
        decay_amount: decay_amount,
        minimum_intimacy: minimum_intimacy
      }

      {:ok, config_map}
    else
      {:error, reason} -> {:error, reason}
    end
  end
end
