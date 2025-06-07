defmodule TetoBot.Interactions.Teto do
  @moduledoc """
  Handles Discord slash command interactions for the `/teto` command.

  This module provides functionality for users to check their intimacy level
  with Teto, view their current relationship tier, see progress toward the next
  tier, and check their feeding cooldown status.

  ## Features

  - Display current intimacy points and relationship tier
  - Show progress toward next relationship tier
  - Check feed cooldown status and time remaining
  - Error handling for database failures
  - Channel whitelisting enforcement

  ## Usage

  This module is typically called from the main slash command dispatcher when
  a user executes the `/teto` command in Discord.

  ## Examples
      TetoBot.Interactions.Teto.handle_teto(interaction, user_id, guild_id, channel_id)

  """

  require Logger

  alias TetoBot.Users
  alias Nostrum.Struct

  alias TetoBot.Format
  alias TetoBot.Intimacy
  alias TetoBot.Interactions.{Permissions, Responses}

  @spec handle_teto(Struct.Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the `/teto` slash command interaction.

  Displays the user's current intimacy level, relationship tier, progress toward
  the next tier, and feeding cooldown status. Only works in whitelisted channels.
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
      case Intimacy.get(guild_id, user_id) do
        {:ok, intimacy} ->
          response = build_intimacy_response(intimacy, guild_id, user_id)
          Responses.success(interaction, response, ephemeral: true)

        {:error, reason} ->
          handle_intimacy_error(interaction, reason)
      end
    end)
  end

  @doc false
  # Builds the formatted response message containing intimacy information.
  defp build_intimacy_response(intimacy, guild_id, user_id) do
    {curr, next} = Intimacy.get_tier_info(intimacy)
    {curr_val, curr_tier} = curr
    {next_val, next_tier} = next

    next_tier_hint_msg = build_next_tier_message(curr_tier, next_tier, curr_val, next_val)
    feed_cooldown_msg = get_feed_cooldown_message(guild_id, user_id)

    """
    **Intimacy:** #{intimacy}
    **Relationship:** #{curr_tier}
    #{next_tier_hint_msg}

    #{feed_cooldown_msg}.
    """
  end

  @doc false
  # Builds the message showing progress toward the next relationship tier.
  defp build_next_tier_message(curr_tier, next_tier, curr_val, next_val) do
    if curr_tier == next_tier do
      "Highest Tier(#{curr_tier}) Reached"
    else
      diff = next_val - curr_val
      "**#{diff}** More Intimacy to Reach Next Tier: #{next_tier}"
    end
  end

  @doc false
  # Gets the formatted feed cooldown status message.
  defp get_feed_cooldown_message(guild_id, user_id) do
    case Users.check_feed_cooldown(guild_id, user_id) do
      {:ok, :allowed} ->
        "You **can** feed Teto now"

      {:error, time_left} when is_integer(time_left) ->
        "The next feed reset is in #{Format.format_time_left(time_left)}"
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
end
