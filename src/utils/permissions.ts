import {
  type ChatInputCommandInteraction,
  PermissionFlagsBits,
} from 'discord.js'
import discordBotApi, { isApiError, isValidationError } from '../services/api'

/**
 * Check if the user has the required permission to manage channels
 */
export function hasManageChannelsPermission(
  interaction: ChatInputCommandInteraction
): boolean {
  if (!interaction.memberPermissions) {
    return false
  }
  return interaction.memberPermissions.has(PermissionFlagsBits.ManageChannels)
}

/**
 * Check if channel is whitelisted
 */
export async function isChannelWhitelisted(
  channelId: string,
  guildId: string
): Promise<boolean> {
  try {
    const result = await discordBotApi.channels.getChannel(channelId)

    if (isApiError(result) || isValidationError(result)) {
      return false
    }

    return result.data.channel.guildId === guildId
  } catch (error) {
    console.error('Error checking channel whitelist:', error)
    return false
  }
}
