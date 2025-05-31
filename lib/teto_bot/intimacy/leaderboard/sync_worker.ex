defmodule TetoBot.Intimacy.Leaderboard.SyncWorker do
  use Oban.Worker, queue: :leaderboard_sync, max_attempts: 3

  require Logger
  alias TetoBot.Guilds
  alias TetoBot.Intimacy.Leaderboard

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Syncing leaderboards to Postgres")

    try do
      sync_to_postgres()
      Logger.info("Leaderboards synced")
      :ok
    rescue
      e ->
        Logger.error("Failed to sync leaderboards: #{inspect(e)}")
        {:error, e}
    end
  end

  defp sync_to_postgres do
    guild_ids = Guilds.ids()

    for guild_id <- guild_ids do
      updated_users_key = "updated_users:#{guild_id}"
      updated_users = Redix.command!(:redix, ["SMEMBERS", updated_users_key])

      unless Enum.empty?(updated_users) do
        leaderboard_key = "leaderboard:#{guild_id}"

        intimacies =
          Redix.pipeline!(:redix, Enum.map(updated_users, &["ZSCORE", leaderboard_key, &1]))

        for {user_id_str, intimacy_str} <- Enum.zip(updated_users, intimacies) do
          user_id = String.to_integer(user_id_str)
          intimacy = String.to_integer(intimacy_str)

          attrs = %{
            guild_id: guild_id,
            user_id: user_id,
            intimacy: intimacy
          }

          %Leaderboard{}
          |> Leaderboard.changeset(attrs)
          |> TetoBot.Repo.insert(
            on_conflict: [set: [intimacy: intimacy]],
            conflict_target: [:guild_id, :user_id]
          )
        end

        Redix.command!(:redix, ["DEL", updated_users_key])
      end
    end
  end
end
