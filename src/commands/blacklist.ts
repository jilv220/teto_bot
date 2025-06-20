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
  .setName('blacklist')
  .setDescription(
    'Remove a channel from the whitelist (requires Manage Channels permission)'
  )
  .addChannelOption((option) =>
    option
      .setName('channel')
      .setDescription('The channel to remove from the whitelist')
      .setRequired(true)
      .addChannelTypes(ChannelType.GuildText)
  )

/**
 * Build appropriate error message based on error type
 */
function buildErrorMessage(error: unknown, channelId: string): string {
  if (isApiError(error) || isValidationError(error)) {
    // Check for specific error cases
    const errorMessage = getErrorMessage(error)

    // Check for "not found" errors
    if (errorMessage.toLowerCase().includes('not found')) {
      return `Channel <#${channelId}> was not found in the whitelist.`
    }

    return `Failed to blacklist channel <#${channelId}>`
  }

  // Handle FetchError (network/HTTP errors)
  if (error instanceof Error) {
    const errorMessage = error.message

    // Check for 404 Not Found status (indicates channel not in whitelist)
    if (errorMessage.includes('404') && errorMessage.includes('Not Found')) {
      return `Channel <#${channelId}> was not found in the whitelist.`
    }
  }

  return `Failed to blacklist channel <#${channelId}>. Please check the logs.`
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
    // Attempt to blacklist the channel by removing it from the database
    const result = await discordBotApi.channels.deleteChannel(channel.id)

    if (isApiError(result) || isValidationError(result)) {
      console.error(`Failed to blacklist channel ${channel.id}:`, result)

      const errorMessage = buildErrorMessage(result, channel.id)
      await interaction.reply({
        content: errorMessage,
        flags: MessageFlags.Ephemeral,
      })
    } else {
      await interaction.reply({
        content: `Channel <#${channel.id}> has been removed from the whitelist.`,
        flags: MessageFlags.Ephemeral,
      })
    }
  } catch (error) {
    console.error(`Failed to blacklist channel ${channel.id}:`, error)
    const errorMessage = buildErrorMessage(error, channel.id)
    await interaction.reply({
      content: errorMessage,
      flags: MessageFlags.Ephemeral,
    })
  }
}
