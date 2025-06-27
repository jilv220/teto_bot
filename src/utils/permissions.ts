import {
  type ChatInputCommandInteraction,
  type GuildChannel,
  type Message,
  PermissionFlagsBits,
  type TextChannel,
} from 'discord.js'
import { Effect, Either } from 'effect'
import { ApiService, ChannelService, type MainLive } from '../services'

/**
 * Check if the user has the required permission to manage channels
 */
export function hasManageChannelsPermissionFromInteraction(
  interaction: ChatInputCommandInteraction
): boolean {
  if (!interaction.memberPermissions) {
    return false
  }
  return interaction.memberPermissions.has(PermissionFlagsBits.ManageChannels)
}

/**
 * Check if the message author has ManageChannels permission in the guild
 */
export function hasManageChannelsPermissionFromMessage(
  message: Message
): boolean {
  if (!message.guild || !message.member) {
    return false
  }

  return message.member.permissions.has(PermissionFlagsBits.ManageChannels)
}

/**
 * Check if the bot should respond to a message
 * Combines all filtering logic: bot check, guild check, mention check, and permissions
 */
export function canBotSendMessages(message: Message): boolean {
  // Ignore messages from bots (including ourselves)
  if (message.author.bot) return false

  // Only handle guild messages (ignore DMs)
  if (!message.guildId) {
    return false
  }

  // Check if the bot is mentioned
  if (!message.mentions.has(message.client.user)) {
    return false // Not mentioned, ignore
  }

  const channel = message.channel
  const guild = message.guild

  // For DM channels, we should be able to send messages
  if (!guild || !channel) {
    return false
  }

  // Check if it's a guild channel with permissions
  if (!('permissionsFor' in channel)) {
    return true // DM channels or other non-guild channels
  }

  const botMember = guild.members.me
  if (!botMember) {
    return false
  }

  try {
    const permissions = (channel as TextChannel).permissionsFor(botMember)
    if (!permissions) {
      return false
    }

    // Check for both view and send permissions individually
    const hasViewChannel = permissions.has(PermissionFlagsBits.ViewChannel)
    const hasSendMessages = permissions.has(PermissionFlagsBits.SendMessages)

    // Debug logging for permission issues
    if (!hasViewChannel || !hasSendMessages) {
      console.log(`Permission check failed for channel ${channel.id}:`, {
        hasViewChannel,
        hasSendMessages,
        botId: botMember.id,
        guildId: guild.id,
      })
    }

    return hasViewChannel && hasSendMessages
  } catch (error) {
    // If we can't check permissions, assume we don't have them
    console.log(`Permission check error for channel ${channel.id}:`, error)
    return false
  }
}
