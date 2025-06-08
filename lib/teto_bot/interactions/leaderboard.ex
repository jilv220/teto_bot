defmodule TetoBot.Interactions.Leaderboard do
  @moduledoc """
  Handles leaderboard-related functionality for Discord interactions.
  """

  require Logger

  alias Nostrum.Api
  alias TetoBot.Accounts
  alias TetoBot.Interactions.Responses

  @api_timeout 2000
  @task_timeout 1500

  @spec handle_leaderboard(Nostrum.Struct.Interaction.t(), integer()) :: :ok | Api.error()
  @doc """
  Handles the leaderboard command interaction.
  """
  def handle_leaderboard(interaction, guild_id) do
    case Accounts.get_leaderboard(guild_id) do
      {:ok, []} ->
        Responses.success(interaction, "No one has earned intimacy with Teto in this guild yet!")

      {:ok, entries} ->
        build_and_send_leaderboard(interaction, guild_id, entries)

      {:error, reason} ->
        Logger.error("Failed to fetch leaderboard for guild #{guild_id}: #{inspect(reason)}")

        Responses.error(
          interaction,
          "Failed to retrieve the leaderboard. Please try again later."
        )
    end
  end

  @spec build_and_send_leaderboard(Nostrum.Struct.Interaction.t(), integer(), list()) ::
          :ok | Api.error()
  defp build_and_send_leaderboard(interaction, guild_id, entries) do
    user_ids = Enum.map(entries, & &1.user_id)

    case fetch_user_data_concurrently(guild_id, user_ids) do
      {:ok, {members_map, users_map}} ->
        leaderboard_text = build_leaderboard_text(entries, members_map, users_map)
        Responses.success(interaction, leaderboard_text)

      {:error, :timeout} ->
        Responses.error(
          interaction,
          "The leaderboard is temporarily unavailable due to slow Discord API response. Please try again later."
        )

      {:error, reason} ->
        Logger.error("Failed to fetch user data for leaderboard: #{inspect(reason)}")

        Responses.error(
          interaction,
          "Failed to retrieve the leaderboard. Please try again later."
        )
    end
  end

  defp fetch_user_data_concurrently(guild_id, user_ids) do
    parent = self()

    task =
      Task.async(fn ->
        # Fetch guild members and users concurrently
        member_task = Task.async(fn -> Api.Guild.members(guild_id, limit: 1000) end)
        user_tasks = Enum.map(user_ids, &Task.async(fn -> Api.User.get(&1) end))

        # Await results
        {:ok, members} = Task.await(member_task, @api_timeout)
        users = Task.await_many(user_tasks, @api_timeout)

        # Process results
        members_map =
          members
          |> Enum.map(fn m -> {m.user_id, m} end)
          |> Map.new()

        users_map =
          users
          |> Enum.map(fn {:ok, u} -> {u.id, u} end)
          |> Map.new()

        send(parent, {:user_data_fetched, {:ok, {members_map, users_map}}})
      end)

    receive do
      {:user_data_fetched, result} ->
        Task.shutdown(task)
        result
    after
      @task_timeout ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp build_leaderboard_text(entries, members_map, users_map) do
    leaderboard_entries =
      entries
      |> Enum.with_index(1)
      |> Enum.map(fn {%{user_id: user_id, intimacy: intimacy}, rank} ->
        display_name = get_display_name(user_id, members_map, users_map)
        "#{rank}. #{display_name} - #{intimacy}"
      end)

    leaderboard = Enum.join(leaderboard_entries, "\n")

    """
    **Teto's Intimacy Leaderboard (Top 10)**

    #{leaderboard}
    """
  end

  defp get_display_name(user_id, members_map, users_map) do
    # Try nickname from guild member first
    case Map.get(members_map, user_id) do
      %{nick: nick} when not is_nil(nick) ->
        nick

      _ ->
        # Fall back to user global name or username
        case Map.get(users_map, user_id) do
          %{global_name: global_name} when not is_nil(global_name) -> global_name
          %{username: username} when not is_nil(username) -> username
          _ -> "User##{user_id}"
        end
    end
  end
end
