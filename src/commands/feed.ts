import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import {
  type UserGuild,
  discordBotApi,
  isApiError,
  isValidationError,
} from '../services/api'
import {
  buildFeedCooldownMessage,
  buildFeedSuccessMessage,
  checkFeedCooldown,
} from '../services/feed'
import { FEED_INTIMACY_GAIN } from '../services/teto'
import { isChannelWhitelisted } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('feed')
  .setDescription('Feed Teto to increase your intimacy with her')

/**
 * Execute the feed command
 */
async function executeFeedCommand(
  interaction: ChatInputCommandInteraction,
  userId: string,
  guildId: string
): Promise<void> {
  try {
    // First ensure user exists and get current user guild data
    const ensureResult = await discordBotApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    if (isApiError(ensureResult) || isValidationError(ensureResult)) {
      console.error('Failed to ensure user exists:', ensureResult)
      await interaction.reply({
        content: 'Something went wrong while feeding Teto. Please try again.',
        flags: MessageFlags.Ephemeral,
      })
      return
    }

    const userGuild = ensureResult.data.userGuild

    // Check feed cooldown
    const cooldownCheck = checkFeedCooldown(userGuild.lastFeed)
    if (!cooldownCheck.allowed) {
      await interaction.reply({
        content: buildFeedCooldownMessage(cooldownCheck.timeLeft),
        flags: MessageFlags.Ephemeral,
      })
      return
    }

    // Update intimacy and last feed time
    const newIntimacy = userGuild.intimacy + FEED_INTIMACY_GAIN
    const updateResult = await discordBotApi.userGuilds.updateUserGuild(
      userId,
      guildId,
      {
        intimacy: newIntimacy,
        lastFeed: new Date().toISOString(),
      }
    )

    if (isApiError(updateResult) || isValidationError(updateResult)) {
      console.error(
        `Failed to feed Teto for user ${userId} in guild ${guildId}:`,
        updateResult
      )
      await interaction.reply({
        content: 'Something went wrong while feeding Teto. Please try again.',
        flags: MessageFlags.Ephemeral,
      })
      return
    }

    // Success!
    const successMessage = buildFeedSuccessMessage(
      updateResult.data.userGuild.intimacy
    )
    await interaction.reply({
      content: successMessage,
      flags: MessageFlags.Ephemeral,
    })
  } catch (error) {
    console.error(
      `Failed to feed Teto for user ${userId} in guild ${guildId}:`,
      error
    )
    await interaction.reply({
      content: 'Something went wrong while feeding Teto. Please try again.',
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

  // Check if channel is whitelisted
  const isWhitelisted = await isChannelWhitelisted(channelId, guildId)
  if (!isWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  await executeFeedCommand(interaction, userId, guildId)
}
