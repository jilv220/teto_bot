defmodule TetoBot.Interactions.Teto do
  @moduledoc """
  Handles Discord slash command interactions for the `/teto` command.

  This module provides comprehensive functionality for users to check their intimacy level
  with Teto, view their current relationship tier, see progress toward the next
  tier, check their feeding cooldown status, and view their daily message limits and voting status.

  ## Features

  - Display current intimacy points and relationship tier
  - Show progress toward next relationship tier
  - Check feed cooldown status and time remaining
  - Display daily message limits and remaining messages
  - Show voting status and benefits
  - Error handling for database failures
  - Channel whitelisting enforcement

  ## Usage

  This module is typically called from the main slash command dispatcher when
  a user executes the `/teto` command in Discord.

  ## Examples
      TetoBot.Interactions.Teto.handle_teto(interaction)

  """

  require Logger

  alias TetoBot.Accounts
  alias Nostrum.Struct

  alias TetoBot.Format
  alias TetoBot.Interactions.{Permissions, Responses}
  alias TetoBot.RateLimiting

  @spec handle_teto(Struct.Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the `/teto` slash command interaction.

  Displays the user's comprehensive status including intimacy level, relationship tier,
  progress toward the next tier, feeding cooldown status, daily message limits, and voting status.
  Only works in whitelisted channels.
  """
  def handle_teto(
        %Struct.Interaction{
          data: %{name: "teto"},
          user: %Struct.User{id: user_id},
          guild_id: guild_id,
          channel_id: channel_id
        } = interaction
      ) do
    Permissions.with_whitelisted_channel(interaction, channel_id, fn ->
      case {Accounts.get_metrics(guild_id, user_id), RateLimiting.get_user_status(user_id)} do
        {{:ok, metrics}, {:ok, status}} ->
          response = build_combined_response(metrics, status, guild_id, user_id)
          Responses.success(interaction, response, ephemeral: true)

        {{:error, reason}, _} ->
          handle_intimacy_error(interaction, reason)

        {_, {:error, reason}} ->
          handle_status_error(interaction, reason)
      end
    end)
  end

  @doc false
  # Builds the comprehensive response message containing both intimacy and status information.
  defp build_combined_response(
         {intimacy, daily_message_count} = _metrics,
         %{
           message_credits: credits,
           has_voted: has_voted
         } = _status,
         guild_id,
         user_id
       ) do
    intimacy_section = build_intimacy_section(intimacy, daily_message_count, guild_id, user_id)
    message_status_section = build_message_status_section(credits)
    voting_status_section = build_voting_status_section(has_voted)
    reset_info = "🕛 Daily credit refill happens at **midnight UTC (12am)** each day."

    intimacy_section <> message_status_section <> voting_status_section <> reset_info
  end

  @doc false
  # Builds the intimacy and relationship information section.
  defp build_intimacy_section(intimacy, daily_message_count, guild_id, user_id) do
    {curr, next} = Accounts.get_tier_info(intimacy)
    {curr_val, curr_tier} = curr
    {next_val, next_tier} = next

    next_tier_hint_msg = build_next_tier_message(curr_tier, next_tier, curr_val, next_val)
    feed_cooldown_msg = get_feed_cooldown_message(guild_id, user_id)

    "💖 **Your Relationship with Teto**\n\n" <>
      "• **Intimacy:** #{intimacy}\n" <>
      "• **Relationship:** #{curr_tier}\n" <>
      "• #{next_tier_hint_msg}\n" <>
      "• #{feed_cooldown_msg}\n" <>
      "• You have talked to Teto __#{daily_message_count}__ times today in this guild\n\n"
  end

  @doc false
  # Builds the daily message status section.
  defp build_message_status_section(credits) do
    "💳 **Your Message Credits**\n\n" <>
      "• Credits available: **#{credits}**\n" <>
      "• Each message costs 1 credit\n\n"
  end

  @doc false
  # Builds the voting status section.
  defp build_voting_status_section(is_voted) do
    if is_voted do
      "✅ **Voting Status**: Active (voted within 12 hours)\n" <>
        "🎉 Thanks for voting! You can vote again after 12 hours to get **#{RateLimiting.get_vote_credit_bonus()} more credits**!\n\n"
    else
      "❌ **Voting Status**: Not voted recently\n" <>
        "💡 Vote for the bot on [top.gg](#{TetoBot.Constants.vote_url()}) " <>
        "to get **#{RateLimiting.get_vote_credit_bonus()} credits** immediately!\n\n"
    end
  end

  @doc false
  # Builds the message showing progress toward the next relationship tier.
  defp build_next_tier_message(curr_tier, next_tier, curr_val, next_val) do
    if curr_tier == next_tier do
      "**Status:** Highest Tier (#{curr_tier}) Reached"
    else
      diff = next_val - curr_val
      "**Next Tier:** __#{diff}__ more intimacy to reach #{next_tier}"
    end
  end

  @doc false
  # Gets the formatted feed cooldown status message.
  defp get_feed_cooldown_message(guild_id, user_id) do
    case Accounts.check_feed_cooldown(guild_id, user_id) do
      {:ok, :allowed} ->
        "**Feed Status:** You can feed Teto now"

      {:error, time_left} when is_integer(time_left) ->
        "**Feed Status:** Next feed available in #{Format.format_time_left(time_left)}"
    end
  end

  @spec handle_intimacy_error(Struct.Interaction.t(), any()) :: :ok | Nostrum.Api.error()
  @doc false
  # Handles errors when retrieving intimacy information from the database.
  defp handle_intimacy_error(
         %Struct.Interaction{
           data: %{name: "teto"},
           user: %Struct.User{id: user_id},
           guild_id: guild_id
         } = interaction,
         reason
       ) do
    Logger.error(
      "Failed to get intimacy info for user #{user_id} in guild #{guild_id}: #{inspect(reason)}"
    )

    Responses.error(
      interaction,
      "Something went wrong while retrieving user intimacy info. Please try again later."
    )
  end

  @spec handle_status_error(Struct.Interaction.t(), any()) :: :ok | Nostrum.Api.error()
  @doc false
  # Handles errors when retrieving status information from the rate limiter.
  defp handle_status_error(
         %Struct.Interaction{
           user: %Struct.User{id: user_id}
         } = interaction,
         reason
       ) do
    Logger.error("Failed to get status for user #{user_id}: #{inspect(reason)}")

    Responses.error(
      interaction,
      "Something went wrong while retrieving your message status. Please try again later."
    )
  end
end
