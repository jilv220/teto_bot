import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import {
  type DiscordUserData,
  type UserMetrics,
  type UserStatus,
  buildTetoStatusEmbed,
} from '../embeds/teto'
import { discordBotApi } from '../services/api'
import { hasVotedRecently } from '../services/voting'
import { isChannelWhitelisted } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('teto')
  .setDescription(
    'Check your intimacy level with Teto, relationship tier, feed status, and message credits'
  )

/**
 * Handle intimacy error
 */
async function handleIntimacyError(
  interaction: ChatInputCommandInteraction,
  userId: string,
  guildId: string,
  reason: unknown
): Promise<void> {
  console.error(
    `Failed to get intimacy info for user ${userId} in guild ${guildId}:`,
    reason
  )

  await interaction.reply({
    content:
      'Something went wrong while retrieving user intimacy info. Please try again later.',
    flags: MessageFlags.Ephemeral,
  })
}

/**
 * Handle status error
 */
async function handleStatusError(
  interaction: ChatInputCommandInteraction,
  userId: string,
  reason: unknown
): Promise<void> {
  console.error(`Failed to get status for user ${userId}:`, reason)

  await interaction.reply({
    content:
      'Something went wrong while retrieving your message status. Please try again later.',
    flags: MessageFlags.Ephemeral,
  })
}

/**
 * Execute the teto command with channel whitelisting
 */
async function executeTetoCommand(
  interaction: ChatInputCommandInteraction,
  userId: string,
  guildId: string
): Promise<void> {
  try {
    // Ensure user exists
    const { data } = await discordBotApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    const user = data.user
    const userGuild = data.userGuild

    // Extract metrics and status
    const metrics: UserMetrics = {
      intimacy: userGuild.intimacy,
      dailyMessageCount: Number.parseInt(userGuild.dailyMessageCount),
    }

    const status: UserStatus = {
      messageCredits: Number.parseInt(user.messageCredits),
      hasVoted: hasVotedRecently(user.lastVotedAt),
    }

    // Build user data for embed
    const userData: DiscordUserData = {
      username: interaction.user.username,
      avatarURL: interaction.user.displayAvatarURL(),
    }

    // Build and send embed response
    const embed = buildTetoStatusEmbed(
      metrics,
      status,
      { lastFeed: userGuild.lastFeed },
      userData,
      interaction.guild?.name
    )

    await interaction.reply({
      embeds: [embed],
    })
  } catch (error) {
    console.error(
      `Failed to execute teto command for user ${userId} in guild ${guildId}:`,
      error
    )

    await interaction.reply({
      content: 'Something went wrong. Please try again later.',
      flags: MessageFlags.Ephemeral,
    })
  }
}

export async function execute(interaction: ChatInputCommandInteraction) {
  const userId = interaction.user.id
  const guildId = interaction.guildId
  const channelId = interaction.channelId

  if (!guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const isWhitelisted = await isChannelWhitelisted(channelId, guildId)
  if (!isWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  await executeTetoCommand(interaction, userId, guildId)
}
