import type { Message } from 'discord.js'
import { Effect, Runtime } from 'effect'
import { ChannelService, type MainLive } from '../services'
import { canBotSendMessages } from '../utils/permissions'

/**
 * Generate a friendly reminder message for users to use the /teto command
 */
function buildTetoCommandReminderMessage(): string {
  return (
    "Hey there! 🎵 I've switched to slash commands now! " +
    'Use `/teto` followed by your message to chat with me. ' +
    'For example: `/teto Hello Teto!` ✨\n\n' +
    'You can also use `/help` to see all my available commands!'
  )
}

/**
 * Send reminder with proper error handling
 */
async function sendTetoCommandReminder(
  message: Message,
  runtime: Runtime.Runtime<never>
): Promise<void> {
  try {
    await message.reply(buildTetoCommandReminderMessage())
  } catch (error: unknown) {
    // Handle Discord API errors gracefully
    const discordError = error as { code?: number; message?: string }
    if (discordError.code === 50013) {
      Effect.logWarning(
        `Missing permissions to send message in channel ${message.channelId} (guild: ${message.guildId})`
      ).pipe(Runtime.runSync(runtime))
    } else {
      Effect.logError(
        `Failed to send reminder message: ${discordError.message || String(error)}`
      ).pipe(Runtime.runSync(runtime))
    }
  }
}

/**
 * Handle messages to remind users to use slash commands
 * This listener responds to messages and reminds users to use /teto
 * Only responds in whitelisted channels and when bot has permissions
 */
export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (message: Message): Promise<void> => {
    // Ignore messages from bots (including ourselves)
    if (message.author.bot) return

    // Only respond in guild channels (not DMs for now)
    if (!message.guildId) return

    // Check if channel is whitelisted
    const isChannelWhitelisted = await ChannelService.pipe(
      Effect.flatMap(({ isChannelWhitelisted }) =>
        isChannelWhitelisted(message.channelId)
      )
    )
      .pipe(Effect.provide(live), Runtime.runPromise(runtime))
      .catch(() => false) // If check fails, assume not whitelisted

    if (!isChannelWhitelisted) {
      return
    }

    // Check if bot has permission to send messages in this channel
    if (!canBotSendMessages(message)) {
      return
    }

    // Log the interaction attempt
    Effect.logInfo(
      `User ${message.author.username}(${message.author.id}) sent message in whitelisted channel ${message.channelId} (guild: ${message.guildId})`
    ).pipe(Runtime.runSync(runtime))

    // Send reminder message
    await sendTetoCommandReminder(message, runtime)
  }
