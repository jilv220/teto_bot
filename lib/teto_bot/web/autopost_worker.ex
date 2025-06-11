defmodule TetoBot.Web.AutopostWorker do
  @moduledoc """

  """
  alias TetoBot.Guilds
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  require Ash.Query

  @impl Oban.Worker
  def perform(_job) do
    token = Application.get_env(:teto_bot, :topgg_token)

    with {:ok, guild_ids} <- Guilds.guild_ids(),
         {:ok, api} <- TopggEx.Api.new(token),
         {:ok, stat} <- TopggEx.Api.post_stats(api, %{server_count: length(guild_ids)}) do
      Logger.info("Successfully post bot stats to Toppgg: #{inspect(stat)}")
    else
      {:error, reason} ->
        Logger.error("Failed to autopost bot stats to Topgg. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Manually trigger a daily reset job.
  """
  def trigger do
    %{}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
