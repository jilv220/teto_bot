defmodule TetoBot.Interactions do
  @moduledoc """
  Handles Discord interaction-related functionality, such as processing commands and creating responses.
  """

  require Logger

  alias TetoBot.Leaderboards
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
    create_response(interaction, "pong", ephemeral: true)
  end

  def handle_interaction(%Interaction{data: %{name: "help"}} = interaction, _ws_state) do
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

  def handle_interaction(
        %Interaction{data: %{name: "feed"}, guild_id: guild_id, user: %{id: user_id}} =
          interaction,
        _ws_state
      ) do
    if Channels.whitelisted?(interaction.channel_id) do
      case Leaderboards.check_feed_cooldown(guild_id, user_id) do
        {:ok, :allowed} ->
          Leaderboards.increment_intimacy!(guild_id, user_id, 5)
          {:ok, intimacy} = Leaderboards.get_intimacy(guild_id, user_id)

          create_response(
            interaction,
            "You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: #{intimacy}. 💖"
          )

        {:error, time_left} when is_integer(time_left) ->
          time_left_formatted = format_time_left(time_left)

          create_response(
            interaction,
            "You've already fed Teto today! Try again in #{time_left_formatted}."
          )

        {:error, reason} ->
          Logger.error(
            "Failed to check feed cooldown for user #{user_id} in guild #{guild_id}: #{inspect(reason)}"
          )

          create_response(
            interaction,
            "Something went wrong while checking the cooldown. Please try again later.",
            ephemeral: true
          )
      end
    else
      create_response(
        interaction,
        "This command can only be used in whitelisted channels.",
        ephemeral: true
      )
    end
  end

  def handle_interaction(
        %Interaction{data: %{name: "leaderboard"}, guild_id: guild_id} = interaction,
        _ws_state
      ) do
    guild_id_str = Integer.to_string(guild_id)
    leaderboard_key = "leaderboard:#{guild_id_str}"

    case Redix.command(:redix, ["ZREVRANGE", leaderboard_key, 0, 9, "WITHSCORES"]) do
      {:ok, []} ->
        create_response(
          interaction,
          "No one has earned intimacy with Teto in this guild yet!"
        )

      {:ok, entries} ->
        leaderboard =
          Enum.chunk_every(entries, 2)
          |> Enum.with_index(1)
          |> Enum.map(fn {[user_id, intimacy], rank} ->
            "#{rank}. <@#{user_id}> - Intimacy: #{intimacy}"
          end)
          |> Enum.join("\n")

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

  def handle_interaction(%Interaction{data: %{name: "whitelist"}} = interaction, _ws_state) do
    if can_manage_channels?(interaction) do
      channel_id = get_channel_id_from_options(interaction.data.options)

      case Channels.whitelist_channel(channel_id) do
        {:ok, _channel} ->
          create_response(
            interaction,
            "Channel <##{channel_id}> whitelisted successfully!",
            ephemeral: true
          )

        {:error, changeset} ->
          Logger.error("Failed to whitelist channel #{channel_id}: #{inspect(changeset.errors)}")
          {error_msg, _} = changeset.errors |> Keyword.get(:channel_id)

          response_content =
            if is_binary(error_msg) && error_msg |> String.contains?("has already been taken") do
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

  def handle_interaction(%Interaction{data: %{name: "blacklist"}} = interaction, _ws_state) do
    if can_manage_channels?(interaction) do
      channel_id = get_channel_id_from_options(interaction.data.options)

      case Channels.blacklist_channel(channel_id) do
        {:ok, _channel} ->
          create_response(
            interaction,
            "Channel <##{channel_id}> has been removed from the whitelist.",
            ephemeral: true
          )

        {:error, :not_found} ->
          create_response(
            interaction,
            "Channel <##{channel_id}> was not found in the whitelist.",
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

  def handle_interaction(_interaction, _ws_state), do: :ok

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
  Creates an ephemeral response for a Discord interaction.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.
  - content: The string content of the ephemeral response.

  ## Returns
  - The result of Nostrum.Api.Interaction.create_response/2.
  """
  def create_ephemeral_response(interaction, content) do
    create_response(interaction, content, ephemeral: true)
  end

  @doc """
  Checks if the user invoking the interaction has the "Manage Channels" permission.

  ## Parameters
  - interaction: The Nostrum.Struct.Interaction struct.

  ## Returns
  - `true` if the user has "Manage Channels" permission, `false` otherwise.
  """
  def can_manage_channels?(%Interaction{guild_id: guild_id, member: member})
      when not is_nil(guild_id) and not is_nil(member) do
    case Guild.get(guild_id) do
      {:ok, guild} ->
        # Ignore channel permission override, otherwise I ll go bankrupt
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

  ## Private
  defp get_channel_id_from_options(options) do
    Enum.find(options, fn opt -> opt.name == "channel" end).value
  end

  defp format_time_left(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    seconds_left = rem(seconds, 60)

    case {hours, minutes, seconds_left} do
      {0, 0, s} ->
        "#{s} second#{if s != 1, do: "s", else: ""}"

      {0, m, s} ->
        "#{m} minute#{if m != 1, do: "s", else: ""} and #{s} second#{if s != 1, do: "s", else: ""}"

      {h, m, _s} ->
        "#{h} hour#{if h != 1, do: "s", else: ""} and #{m} minute#{if m != 1, do: "s", else: ""}"
    end
  end
end
