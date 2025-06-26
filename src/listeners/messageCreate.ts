import type { Message } from 'discord.js'
import { Effect, Runtime } from 'effect'
import { handleTetoInteraction } from '../commands/teto'
import { ChannelService, type MainLive } from '../services'
import { canBotSendMessages } from '../utils/permissions'

/**
 * Generate a friendly reminder message for users to use the /teto command
 */
function buildTetoCommandReminderMessage(): string {
  return (
    "Hey there! Due to Discord's regulation of privileged intents such as MESSAGE_CONTENT, " +
    "I've switched to slash commands now!\n" +
    'Use `/teto <message> <image>` to chat with me. ' +
    'For example: `/teto Hello Teto!` ✨\n' +
    'Or You can chat with me one-on-one through DM!'
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
 * Handle messages - process DMs naturally and send reminders in guild channels
 */
export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (message: Message): Promise<void> => {
    // Handle partial messages (important for DMs)
    if (message.partial) {
      try {
        await message.fetch()
      } catch (error) {
        Effect.logError(`Failed to fetch partial message: ${error}`).pipe(
          Runtime.runSync(runtime)
        )
        return
      }
    }

    // Ignore messages from bots (including ourselves)
    if (message.author.bot) return

    // Handle DMs naturally - process them as Teto interactions
    if (!message.guildId) {
      // Extract image attachments if any
      const imageAttachment =
        message.attachments.size > 0
          ? Array.from(message.attachments.values()).find((att) =>
              att.contentType?.startsWith('image/')
            )
          : null

      try {
        await handleTetoInteraction(runtime, live, {
          content: message.content,
          imageAttachment: imageAttachment || null,
          userId: message.author.id,
          username: message.author.username,
          channelId: message.channelId,
          guildId: null,
          reply: async (content: string) => {
            await message.reply(content)
          },
          // No deferReply needed for regular messages
        })
      } catch (error) {
        Effect.logError(`Error handling DM: ${error}`).pipe(
          Runtime.runSync(runtime)
        )
      }
      return
    }

    // For guild messages, check if channel is whitelisted and send reminder
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
