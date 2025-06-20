import {
  ChannelType,
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import {
  discordBotApi,
  getErrorMessage,
  isApiError,
  isValidationError,
} from '../services/api'
import { hasManageChannelsPermission } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('whitelist')
  .setDescription(
    'Whitelist a channel for the bot to operate in (requires Manage Channels permission)'
  )
  .addChannelOption((option) =>
    option
      .setName('channel')
      .setDescription('The channel to whitelist')
      .setRequired(true)
      .addChannelTypes(ChannelType.GuildText)
  )

/**
 * Build appropriate error message based on error type
 */
function buildErrorMessage(error: unknown, channelId: string): string {
  if (isApiError(error) || isValidationError(error)) {
    return `Failed to whitelist channel <#${channelId}>`
  }

  // Handle FetchError (network/HTTP errors)
  if (error instanceof Error) {
    const errorMessage = error.message

    // Check for 409 Conflict status (indicates channel already exists)
    if (errorMessage.includes('409') && errorMessage.includes('Conflict')) {
      return `Channel <#${channelId}> is already whitelisted.`
    }
  }

  return `Failed to whitelist channel <#${channelId}>. Please check the logs.`
}

export async function execute(interaction: ChatInputCommandInteraction) {
  // Check permissions
  if (!hasManageChannelsPermission(interaction)) {
    await interaction.reply({
      content: 'You need the "Manage Channels" permission to use this command.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const channel = interaction.options.getChannel('channel', true)

  if (!interaction.guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  try {
    await discordBotApi.discord.ensureUserGuildExists({
      userId: interaction.user.id,
      guildId: interaction.guildId,
    })

    // Attempt to whitelist the channel by creating it in the database
    const result = await discordBotApi.channels.createChannel({
      channelId: channel.id,
      guildId: interaction.guildId,
    })

    if (isApiError(result) || isValidationError(result)) {
      console.error(`Failed to whitelist channel ${channel.id}:`, result)

      const errorMessage = buildErrorMessage(result, channel.id)
      await interaction.reply({
        content: errorMessage,
        flags: MessageFlags.Ephemeral,
      })
    } else {
      await interaction.reply({
        content: `Channel <#${channel.id}> whitelisted successfully!`,
        flags: MessageFlags.Ephemeral,
      })
    }
  } catch (error) {
    console.error(`Failed to whitelist channel ${channel.id}:`, error)
    const errorMessage = buildErrorMessage(error, channel.id)
    await interaction.reply({
      content: errorMessage,
      flags: MessageFlags.Ephemeral,
    })
  }
}
