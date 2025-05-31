defmodule TetoBot.Leaderboards.Sync do
  use GenServer
  require Logger

  alias TetoBot.Guilds
  alias TetoBot.Leaderboards.Leaderboard

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_sync()
    {:ok, state}
  end

  def handle_info(:sync, state) do
    sync_to_postgres()
    schedule_sync()
    {:noreply, state}
  end

  defp schedule_sync do
    sec = 1000
    five_mins = 5 * 60 * sec
    Process.send_after(self(), :sync, five_mins)
  end

  defp sync_to_postgres do
    Logger.info("Syncing leaderboards to Postgres")

    try do
      guild_ids = Guilds.ids()

      for guild_id_str <- guild_ids do
        updated_users_key = "updated_users:#{guild_id_str}"
        updated_users = Redix.command!(:redix, ["SMEMBERS", updated_users_key])

        unless Enum.empty?(updated_users) do
          leaderboard_key = "leaderboard:#{guild_id_str}"

          intimacies =
            Redix.pipeline!(:redix, Enum.map(updated_users, &["ZSCORE", leaderboard_key, &1]))

          for {user_id_str, intimacy_str} <- Enum.zip(updated_users, intimacies) do
            guild_id = String.to_integer(guild_id_str)
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

      Logger.info("Leaderboards synced")
    rescue
      e -> Logger.error("Failed to sync leaderboards: #{inspect(e)}")
    end
  end
end
