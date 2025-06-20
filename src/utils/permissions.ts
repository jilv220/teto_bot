import {
  type ChatInputCommandInteraction,
  type GuildChannel,
  type Message,
  PermissionFlagsBits,
  type TextChannel,
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
 * Check if the bot has permission to send messages in a channel
 */
export function canBotSendMessages(message: Message): boolean {
  const channel = message.channel
  const guild = message.guild

  if (!guild || !channel || !('permissionsFor' in channel)) {
    return false
  }

  const botMember = guild.members.me
  if (!botMember) {
    return false
  }

  const permissions = (channel as TextChannel).permissionsFor(botMember)
  if (!permissions) {
    return false
  }

  return permissions.has([
    PermissionFlagsBits.SendMessages,
    PermissionFlagsBits.ViewChannel,
  ])
}

/**
 * Check if the bot has permission to send messages in a specific channel
 */
export function canBotSendMessagesInChannel(channel: GuildChannel): boolean {
  const guild = channel.guild
  const botMember = guild.members.me

  if (!botMember || !('permissionsFor' in channel)) {
    return false
  }

  const permissions = (channel as TextChannel).permissionsFor(botMember)
  if (!permissions) {
    return false
  }

  return permissions.has([
    PermissionFlagsBits.SendMessages,
    PermissionFlagsBits.ViewChannel,
  ])
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
