defmodule TetoBot.Interactions.Leaderboard do
  @moduledoc """
  Handles leaderboard-related functionality for Discord interactions.
  """

  require Logger

  alias Nostrum.Api
  alias TetoBot.Intimacy
  alias TetoBot.Interactions.Responses

  @max_concurrency 20
  @api_timeout 2000
  @task_timeout 1500

  @spec handle_leaderboard(Nostrum.Struct.Interaction.t(), integer()) :: :ok | Api.error()
  @doc """
  Handles the leaderboard command interaction.
  """
  def handle_leaderboard(interaction, guild_id) do
    case Intimacy.get_leaderboard(guild_id) do
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

  @spec fetch_user_data_concurrently(integer(), list(integer())) ::
          {:ok, {map(), map()}} | {:error, :timeout | term()}
  defp fetch_user_data_concurrently(guild_id, user_ids) do
    # Use regular tasks with proper cleanup
    member_task =
      Task.async(fn ->
        fetch_guild_members_batch(guild_id, user_ids)
      end)

    user_task =
      Task.async(fn ->
        fetch_users_batch(user_ids)
      end)

    try do
      members_map = Task.await(member_task, @api_timeout)
      users_map = Task.await(user_task, @api_timeout)
      {:ok, {members_map, users_map}}
    rescue
      error ->
        Task.shutdown(member_task, :brutal_kill)
        Task.shutdown(user_task, :brutal_kill)
        {:error, error}
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(member_task, :brutal_kill)
        Task.shutdown(user_task, :brutal_kill)
        {:error, :timeout}
    end
  end

  @spec fetch_guild_members_batch(integer(), list(integer())) :: map()
  defp fetch_guild_members_batch(guild_id, user_ids) do
    user_ids
    |> Task.async_stream(
      fn user_id ->
        case Api.Guild.member(guild_id, user_id) do
          {:ok, member} -> {user_id, member}
          {:error, _} -> {user_id, nil}
        end
      end,
      max_concurrency: @max_concurrency,
      timeout: @task_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {user_id, member}}, acc -> Map.put(acc, user_id, member)
      {:exit, _}, acc -> acc
    end)
  end

  @spec fetch_users_batch(list(integer())) :: map()
  defp fetch_users_batch(user_ids) do
    user_ids
    |> Task.async_stream(
      fn user_id ->
        case Api.User.get(user_id) do
          {:ok, user} -> {user_id, user}
          {:error, _} -> {user_id, nil}
        end
      end,
      max_concurrency: @max_concurrency,
      timeout: @task_timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {user_id, user}}, acc -> Map.put(acc, user_id, user)
      {:exit, _}, acc -> acc
    end)
  end

  @spec build_leaderboard_text(list(), map(), map()) :: String.t()
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

  @spec get_display_name(integer(), map(), map()) :: String.t()
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
