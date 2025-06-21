import {
  type ChatInputCommandInteraction,
  type GuildChannel,
  type Message,
  PermissionFlagsBits,
  type TextChannel,
} from 'discord.js'
import { Effect, Either } from 'effect'
import { ApiService, MainLive } from '../services'

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

/**
 * Check if channel is whitelisted
 */
export async function isChannelWhitelisted(
  channelId: string
): Promise<boolean> {
  const result = await ApiService.pipe(
    Effect.flatMap(({ effectApi }) => effectApi.channels.getChannel(channelId))
  ).pipe(Effect.either, Effect.provide(MainLive), Effect.runPromise)

  if (Either.isRight(result)) return true
  return false
}
