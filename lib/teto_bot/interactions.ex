defmodule TetoBot.Interactions do
  @moduledoc """
  Handles Discord interaction-related functionality, such as processing commands and creating responses.
  """

  require Logger

  alias TetoBot.Users
  alias TetoBot.Interactions.Teto
  alias Nostrum.Struct.User
  alias TetoBot.Intimacy
  alias Nostrum.Api
  alias Nostrum.Api.Guild
  alias Nostrum.Struct.Interaction
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
      with {:ok, :allowed} <- Users.check_feed_cooldown(user_id) do
        Users.set_feed_cooldown(guild_id, user_id)
        Intimacy.increment!(guild_id, user_id, 5)
        {:ok, intimacy} = Intimacy.get(guild_id, user_id)

        create_response(
          interaction,
          "You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: #{intimacy}. 💖"
        )
      else
        {:error, time_left} when is_integer(time_left) ->
          create_response(
            interaction,
            "You've already fed Teto today! Try again in #{format_time_left(time_left)}."
          )
      end
    end)
  end

  defp handle_leaderboard(interaction, guild_id) do
    guild_id_str = Integer.to_string(guild_id)
    leaderboard_key = "leaderboard:#{guild_id_str}"

    case Redix.command(:redix, ["ZREVRANGE", leaderboard_key, 0, 9, "WITHSCORES"]) do
      {:ok, []} ->
        create_response(interaction, "No one has earned intimacy with Teto in this guild yet!")

      {:ok, entries} ->
        leaderboard =
          Enum.chunk_every(entries, 2)
          |> Enum.with_index(1)
          |> Enum.map_join("\n", fn {[user_id_str, intimacy], rank} ->
            user_id = String.to_integer(user_id_str)

            with {:ok, member} <- Api.Guild.member(guild_id, user_id),
                 {:ok, user} <- Api.User.get(user_id) do
              maybe_nickname = if member.nick, do: member.nick, else: user.global_name
              "#{rank}. #{maybe_nickname} - #{intimacy}"
            else
              {:error, reason} ->
                Logger.error(
                  "Failed to get nickname or global_name for member #{user_id_str}: #{inspect(reason)}"
                )

                "#{rank}. Unknown - #{intimacy}"
            end
          end)

        message = """
        **Teto's Intimacy Leaderboard (Top 10)**\n
        #{leaderboard}
        """

        create_response(interaction, message)

      {:error, reason} ->
        Logger.error("Failed to fetch leaderboard for guild #{guild_id}: #{inspect(reason)}")

        create_response(
          interaction,
          "Failed to retrieve the leaderboard. Please try again later.",
          ephemeral: true
        )
    end
  end

  defp handle_whitelist(%Interaction{channel_id: channel_id} = interaction) do
    if can_manage_channels?(interaction) do
      case Channels.whitelist_channel(channel_id) do
        {:ok, _channel} ->
          create_response(interaction, "Channel <##{channel_id}> whitelisted successfully!",
            ephemeral: true
          )

        {:error, changeset} ->
          Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(changeset.errors)}")
          {error_msg, _} = Keyword.get(changeset.errors, :channel_id)

          response_content =
            if is_binary(error_msg) && String.contains?(error_msg, "has already been taken") do
              "Channel <##{channel_id}> is already whitelisted."
            else
              "Failed to whitelist channel <##{channel_id}>. Please check the logs."
            end

          create_response(interaction, response_content, ephemeral: true)
      end
    else
      create_response(
        interaction,
        "You do not have permission to use this command. Only users with Manage Channels permission can use this command.",
        ephemeral: true
      )
    end
  end

  defp handle_blacklist(%Interaction{channel_id: channel_id} = interaction) do
    if can_manage_channels?(interaction) do
      case Channels.blacklist_channel(channel_id) do
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

  # Private Helpers

  defp format_time_left(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    seconds_left = rem(seconds, 60)

    case {hours, minutes, seconds_left} do
      {0, 0, s} -> "#{s} second#{if s != 1, do: "s", else: ""}"
      {0, m, s} -> "#{m}m #{s}sec"
      {h, m, _s} -> "#{h}h #{m}min"
    end
  end
end
