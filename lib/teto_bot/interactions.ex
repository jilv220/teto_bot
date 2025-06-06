defmodule TetoBot.Interactions do
  @moduledoc """
  Handles Discord interaction-related functionality, such as processing commands and creating responses.
  """

  require Logger

  alias Nostrum.Api
  alias Nostrum.Api.Guild
  alias Nostrum.Struct.User
  alias Nostrum.Struct.Interaction

  alias TetoBot.Format
  alias TetoBot.Users
  alias TetoBot.Interactions.Teto
  alias TetoBot.Intimacy
  alias TetoBot.Channels
  alias TetoBot.Constants
  alias TetoBot.Commands

  @doc """
  Handles an interaction event by dispatching to the appropriate command handler.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.
  - ws_state: The WebSocket state (passed through for compatibility, unused).

  ## Returns
  - The result of the interaction handler or :ok if unhandled.
  """
  def handle_interaction(%Interaction{data: %{name: "ping"}} = interaction, _ws_state) do
    handle_ping(interaction)
  end

  def handle_interaction(%Interaction{data: %{name: "help"}} = interaction, _ws_state) do
    handle_help(interaction)
  end

  def handle_interaction(
        %Interaction{
          data: %{name: "teto"}
        } = interaction,
        _ws_state
      ) do
    Teto.handle_teto(interaction)
  end

  def handle_interaction(
        %Interaction{
          data: %{name: "feed"},
          user: %User{id: user_id},
          guild_id: guild_id,
          channel_id: channel_id
        } = interaction,
        _ws_state
      ) do
    handle_feed(interaction, user_id, guild_id, channel_id)
  end

  def handle_interaction(
        %Interaction{data: %{name: "leaderboard"}, guild_id: guild_id} = interaction,
        _ws_state
      ) do
    handle_leaderboard(interaction, guild_id)
  end

  def handle_interaction(%Interaction{data: %{name: "whitelist"}} = interaction, _ws_state) do
    handle_whitelist(interaction)
  end

  def handle_interaction(%Interaction{data: %{name: "blacklist"}} = interaction, _ws_state) do
    handle_blacklist(interaction)
  end

  def handle_interaction(_interaction, _ws_state), do: :ok

  # Command Handlers

  defp handle_ping(interaction) do
    create_response(interaction, "pong", ephemeral: true)
  end

  defp handle_help(interaction) do
    help_message = """
    **TetoBot Help**

    TetoBot cosplays as Kasane Teto, responding to messages in whitelisted channels with AI-generated replies.

    **Commands:**
    #{Enum.map_join(Commands.commands(), "\n", fn cmd ->
      options = if Map.has_key?(cmd, :options), do: " " <> Enum.map_join(cmd.options, " ", &"<#{&1.name}>"), else: ""
      "- `/#{cmd.name}#{options}`: #{cmd.description}"
    end)}

    **Support:**
    For issues or feedback, please create an issue in our [Github Repo](https://github.com/jilv220/teto_bot/issues)
    """

    create_response(interaction, help_message, ephemeral: true)
  end

  defp handle_feed(interaction, user_id, guild_id, channel_id) do
    with_whitelisted_channel(interaction, channel_id, fn ->
      case Users.check_feed_cooldown(guild_id, user_id) do
        {:ok, :allowed} ->
          Users.set_feed_cooldown(guild_id, user_id)
          Intimacy.increment(guild_id, user_id, 5)
          {:ok, intimacy} = Intimacy.get(guild_id, user_id)

          create_response(
            interaction,
            "You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: #{intimacy}. 💖"
          )

        {:error, time_left} ->
          create_response(
            interaction,
            "You've already fed Teto today! Try again in #{Format.format_time_left(time_left)}."
          )
      end
    end)
  end

  defp handle_leaderboard(interaction, guild_id) do
    case Intimacy.get_leaderboard(guild_id) do
      {:ok, []} ->
        create_response(interaction, "No one has earned intimacy with Teto in this guild yet!")

      {:ok, entries} ->
        # Extract user IDs for batch processing
        user_ids = Enum.map(entries, & &1.user_id)

        # Batch fetch all guild members and users concurrently
        member_tasks = Task.async(fn -> fetch_guild_members_batch(guild_id, user_ids) end)
        user_tasks = Task.async(fn -> fetch_users_batch(user_ids) end)

        try do
          [members_map, users_map] = Task.await_many([member_tasks, user_tasks], 2000)

          # Build leaderboard entries
          leaderboard_entries =
            entries
            |> Enum.with_index(1)
            |> Enum.map(fn {%{user_id: user_id, intimacy: intimacy}, rank} ->
              display_name = get_display_name_from_maps(user_id, members_map, users_map)
              "#{rank}. #{display_name} - #{intimacy}"
            end)

          leaderboard = Enum.join(leaderboard_entries, "\n")

          message = """
          **Teto's Intimacy Leaderboard (Top 10)**

          #{leaderboard}
          """

          create_response(interaction, message)
        catch
          :exit, {:timeout, _} ->
            create_response(
              interaction,
              "The leaderboard is temporarily unavailable due to slow Discord API response. Please try again later.",
              ephemeral: true
            )
        end

      {:error, reason} ->
        Logger.error("Failed to fetch leaderboard for guild #{guild_id}: #{inspect(reason)}")

        create_response(
          interaction,
          "Failed to retrieve the leaderboard. Please try again later.",
          ephemeral: true
        )
    end
  end

  # Batch fetch guild members concurrently
  defp fetch_guild_members_batch(guild_id, user_ids) do
    user_ids
    |> Task.async_stream(
      fn user_id ->
        case Api.Guild.member(guild_id, user_id) do
          {:ok, member} -> {user_id, member}
          {:error, _} -> {user_id, nil}
        end
      end,
      max_concurrency: 15,
      timeout: 1500,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {user_id, member}}, acc -> Map.put(acc, user_id, member)
      {:exit, _}, acc -> acc
    end)
  end

  # Batch fetch users concurrently
  defp fetch_users_batch(user_ids) do
    user_ids
    |> Task.async_stream(
      fn user_id ->
        case Api.User.get(user_id) do
          {:ok, user} -> {user_id, user}
          {:error, _} -> {user_id, nil}
        end
      end,
      max_concurrency: 15,
      timeout: 1500,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {user_id, user}}, acc -> Map.put(acc, user_id, user)
      {:exit, _}, acc -> acc
    end)
  end

  # Get display name from the pre-fetched maps
  defp get_display_name_from_maps(user_id, members_map, users_map) do
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

  defp handle_whitelist(%Interaction{guild_id: guild_id, channel_id: channel_id} = interaction) do
    with_manage_channels(interaction, fn ->
      case Channels.whitelist_channel(guild_id, channel_id) do
        {:ok, _channel} ->
          create_response(interaction, "Channel <##{channel_id}> whitelisted successfully!",
            ephemeral: true
          )

        {:error, changeset} ->
          Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(changeset.errors)}")

          create_response(interaction, whitelist_error_message(changeset, channel_id),
            ephemeral: true
          )
      end
    end)
  end

  defp whitelist_error_message(changeset, channel_id) do
    {error_msg, _} = Keyword.get(changeset.errors, :channel_id)

    if is_binary(error_msg) && String.contains?(error_msg, "has already been taken") do
      "Channel <##{channel_id}> is already whitelisted."
    else
      "Failed to whitelist channel <##{channel_id}>. Please check the logs."
    end
  end

  defp handle_blacklist(%Interaction{guild_id: guild_id, channel_id: channel_id} = interaction) do
    if can_manage_channels?(interaction) do
      case Channels.blacklist_channel(guild_id, channel_id) do
        {:ok, _channel} ->
          create_response(
            interaction,
            "Channel <##{channel_id}> has been removed from the whitelist.",
            ephemeral: true
          )

        {:error, :not_found} ->
          create_response(interaction, "Channel <##{channel_id}> was not found in the whitelist.",
            ephemeral: true
          )

        {:error, reason} ->
          Logger.error("Failed to blacklist channel <##{channel_id}>: #{inspect(reason)}")

          create_response(
            interaction,
            "An error occurred while trying to remove channel <##{channel_id}> from the whitelist.",
            ephemeral: true
          )
      end
    else
      create_response(
        interaction,
        "You do not have permission to use this command. Only users with Manage Channels permission can use this command.",
        ephemeral: true
      )
    end
  end

  # Helpers

  @spec create_response(Interaction.t(), binary(), Keyword.t()) :: :ok | Api.error()
  @doc """
  Creates a response for a Discord interaction.
  """
  def create_response(interaction, content, opts \\ []) do
    ephemeral = Keyword.get(opts, :ephemeral)
    flags = if ephemeral, do: Constants.ephemeral_flag(), else: nil

    response = %{
      type: Constants.interaction_response_type(),
      data: %{
        content: content,
        flags: flags
      }
    }

    Api.Interaction.create_response(interaction, response)
  end

  @doc """
  Checks if the user invoking the interaction has the "Manage Channels" permission.
  """
  def can_manage_channels?(%Interaction{guild_id: guild_id, member: member})
      when not is_nil(guild_id) and not is_nil(member) do
    case Guild.get(guild_id) do
      {:ok, guild} ->
        :manage_channels in Nostrum.Struct.Guild.Member.guild_permissions(member, guild)

      {:error, reason} ->
        Logger.error("Failed to get guild: #{inspect(reason)}")
        false
    end
  end

  def can_manage_channels?(_interaction) do
    Logger.debug("Interaction lacks guild or member data, denying permission")
    false
  end

  def with_whitelisted_channel(interaction, channel_id, fun) do
    if Channels.whitelisted?(channel_id) do
      fun.()
    else
      create_response(interaction, "This command can only be used in whitelisted channels.",
        ephemeral: true
      )
    end
  end

  def with_manage_channels(interaction, fun) do
    if can_manage_channels?(interaction) do
      fun.()
    else
      create_response(
        interaction,
        "You do not have permission to use this command. Only users with Manage Channels permission can use this command.",
        ephemeral: true
      )
    end
  end
end
