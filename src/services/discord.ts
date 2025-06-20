/**
 * Discord related services
 */

import type { Message } from 'discord.js'
import { Data, Effect, Runtime } from 'effect'

export class DiscordMessageErorr extends Data.TaggedError(
  'DiscordMessageError'
)<{
  message: unknown
}> {}

/**
 * Safely reply to a Discord message with proper error handling for permission issues
 */
export async function safeReply(
  message: Message,
  content: string,
  runtime: Runtime.Runtime<never>
): Promise<boolean> {
  try {
    await message.reply(content)
    return true
  } catch (error: unknown) {
    // Handle specific Discord API errors
    const discordError = error as { code?: number; message?: string }
    if (discordError.code === 50013) {
      Effect.logWarning(
        `Missing permissions to send message in channel ${message.channelId} (guild: ${message.guildId})`
      ).pipe(Runtime.runSync(runtime))
    } else if (discordError.code === 50001) {
      Effect.logWarning(
        `Missing access to channel ${message.channelId} (guild: ${message.guildId})`
      ).pipe(Runtime.runSync(runtime))
    } else if (discordError.code === 10003) {
      Effect.logWarning(
        `Unknown channel ${message.channelId} (guild: ${message.guildId})`
      ).pipe(Runtime.runSync(runtime))
    } else {
      Effect.logError(
        `Failed to send message reply: ${discordError.message || String(error)}`
      ).pipe(Runtime.runSync(runtime))
    }
    return false
  }
}
