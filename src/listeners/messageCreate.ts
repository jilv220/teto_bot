import type { Message } from 'discord.js'
import { Effect, Runtime } from 'effect'
import type { MainLive } from '../services'

/**
 * Generate a friendly reminder message for users to use the /teto command
 */
function buildTetoCommandReminderMessage(): string {
  return (
    "Hey there! Due to Discord's regulation of privileged intents such as MESSAGE_CONTENT," +
    "I've switched to slash commands now! " +
    'Use `/teto <message> <image>` followed by your message to chat with me. ' +
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
 * It reminds users to use /teto instead of old interaction methods
 */
export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (message: Message): Promise<void> => {
    // Ignore messages from bots (including ourselves)
    if (message.author.bot) return

    // Log the interaction attempt
    Effect.logInfo(
      `User ${message.author.username}(${message.author.id}) tried to interact via message in guild ${message.guildId}`
    ).pipe(Runtime.runSync(runtime))

    // Send reminder message
    await sendTetoCommandReminder(message, runtime)
  }
