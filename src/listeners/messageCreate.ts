import { type AIMessageChunk, HumanMessage } from '@langchain/core/messages'
import type { Attachment, Message } from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { ApiService, ChannelService, type MainLive } from '../services'
import { ChannelRateLimiter } from '../services/channelRateLimiter'
import { appConfig, isProduction } from '../services/config'
import { LLMContext } from '../services/llm'
import { processImageAttachments } from '../services/llm/attachment'
import {
  buildPromptInjectionFallbackMessage,
  buildPromptInjectionMessage,
} from '../services/llm/prompt'
import { containsInjection } from '../services/messages/filter'
import { canBotSendMessages } from '../utils/permissions'

const createLLMResponse = (
  content: string,
  imageAttachment: Attachment | null,
  intimacy: number,
  username: string,
  channelId: string
) =>
  Effect.gen(function* () {
    const llm = yield* LLMContext

    // Process any image attachments
    const imageContent = imageAttachment
      ? yield* processImageAttachments([imageAttachment])
      : []
    const hasImages = imageContent.length > 0

    // Create message content - either just text or multimodal
    const messageContent = hasImages
      ? [
          {
            type: 'text' as const,
            text: content || '',
          },
          imageContent[0],
        ]
      : content

    // Create simplified user context with just username and intimacy level
    const userContext = {
      username: username,
      intimacy: intimacy,
    }

    // One thread per channel basically
    const config = { configurable: { thread_id: channelId } }

    const result = yield* Effect.promise(() =>
      llm.invoke(
        {
          messages: [new HumanMessage({ content: messageContent })],
          hasImages,
          userContext,
        },
        config
      )
    )

    const lastMessage = result.messages[
      result.messages.length - 1
    ] as AIMessageChunk
    yield* Effect.logInfo(`Response from LLM: ${lastMessage.content}`)

    return lastMessage
  }).pipe(Effect.tapError((error) => Effect.logError(error)))

/**
 * Handle Teto interactions for @mentions in guild channels
 */
const handleTetoInteraction = async (
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  options: {
    content: string
    imageAttachment?: Attachment | null
    userId: string
    username: string
    channelId: string
    guildId: string
    reply: (content: string) => Promise<void>
  }
): Promise<void> => {
  const {
    content,
    imageAttachment,
    userId,
    username,
    channelId,
    guildId,
    reply,
  } = options

  Effect.logInfo(
    `User: ${username}(${userId}) interacted with Teto via @mention in guild ${guildId}`
  ).pipe(Effect.provide(live), Runtime.runSync(runtime))

  // Check if channel is whitelisted
  const isChannelWhitelisted = await ChannelService.pipe(
    Effect.flatMap(({ isChannelWhitelisted }) =>
      isChannelWhitelisted(channelId)
    )
  ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

  if (!isChannelWhitelisted) {
    await reply('This channel is not whitelisted for Teto interactions!')
    return
  }

  // RateLimit channel
  const rateLimitRes = ChannelRateLimiter.pipe(
    Effect.flatMap((limiter) =>
      Effect.all({
        isRateLimited: limiter.isRateLimited(channelId),
        timeUntilReset: limiter.getTimeUntilReset(channelId),
      })
    )
  ).pipe(Effect.provide(live), Runtime.runSync(runtime))

  // Send RateLimit Msg
  if (rateLimitRes.isRateLimited) {
    const secondsUntilReset = Math.ceil(rateLimitRes.timeUntilReset / 1000)
    await reply(
      `This channel is being rate limited. Please wait ${secondsUntilReset} seconds before sending another message.`
    )
    return
  }

  try {
    // Record user message
    const userMsgRecordRes = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.recordUserMessage({
          userId: userId,
          guildId: guildId,
          intimacyIncrement: 1,
        })
      )
    ).pipe(
      Effect.tap((resp) =>
        Effect.logInfo(
          `Recording message - User: ${username}(${userId}) from Guild: ${guildId}`
        )
      ),
      Effect.mapError((error) => {
        if (error.statusCode === 402) return 'not enough credit' as const
        return 'fail to record user message' as const
      }),
      Effect.either,
      Effect.provide(live),
      Runtime.runPromise(runtime)
    )

    const config = Effect.runSync(appConfig)
    if (
      isProduction &&
      Either.isLeft(userMsgRecordRes) &&
      userMsgRecordRes.left === 'not enough credit'
    ) {
      await reply(
        `You've run out of message credits! Vote for the bot to get more credits.\n${config.voteUrl}`
      )
      return
    }

    // Check for prompt injection attempts
    if (containsInjection(content)) {
      Effect.logWarning(
        `Prompt injection detected from user ${username}(${userId}) in guild ${guildId}: "${content}"`
      ).pipe(Runtime.runSync(runtime))

      const teasingResponse = await createLLMResponse(
        buildPromptInjectionMessage(),
        null,
        0, // Use intimacy level 0 for injection attempts
        username,
        channelId
      )
        .pipe(Effect.provide(live), Runtime.runPromise(runtime))
        .catch(() => {
          // Fallback to static message if LLM fails
          return {
            content: buildPromptInjectionFallbackMessage(),
          }
        })

      await reply(String(teasingResponse.content))
      return
    }

    // Get user intimacy for LLM context
    const intimacy =
      userMsgRecordRes._tag === 'Right'
        ? userMsgRecordRes.right.data.userGuild?.intimacy || 0
        : 0

    // Generate LLM response
    const response = await createLLMResponse(
      content,
      imageAttachment || null,
      intimacy,
      username,
      channelId
    ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

    await reply(String(response.content))
  } catch (error) {
    Effect.logError(`Error in Teto interaction: ${error}`).pipe(
      Runtime.runSync(runtime)
    )

    try {
      await reply(
        'Sorry, I encountered an error while processing your message. Please try again later.'
      )
    } catch (replyError) {
      Effect.logError(`Failed to send error reply: ${replyError}`).pipe(
        Runtime.runSync(runtime)
      )
    }
  }
}

/**
 * Handle messages - only respond to @mentions in guild channels
 */
export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (message: Message): Promise<void> => {
    // Ignore messages from bots (including ourselves)
    if (message.author.bot) return

    // Only handle guild messages (ignore DMs)
    if (!message.guildId) {
      return
    }

    // Check if the bot is mentioned
    if (!message.mentions.has(message.client.user)) {
      return // Not mentioned, ignore
    }

    // Check if bot has permission to send messages in this channel
    if (!canBotSendMessages(message)) {
      return
    }

    // Extract image attachments if any
    const imageAttachment =
      message.attachments.size > 0
        ? Array.from(message.attachments.values()).find((att) =>
            att.contentType?.startsWith('image/')
          )
        : null

    // Remove the bot mention from the content to get the actual message
    const botMention = `<@${message.client.user.id}>`
    const botNicknameMention = `<@!${message.client.user.id}>`
    const content = message.content
      .replace(botMention, '')
      .replace(botNicknameMention, '')
      .trim()

    // If there's no content after removing the mention, just skip
    if (!content && !imageAttachment) {
      return
    }

    try {
      await handleTetoInteraction(runtime, live, {
        content,
        imageAttachment: imageAttachment || null,
        userId: message.author.id,
        username: message.author.username,
        channelId: message.channelId,
        guildId: message.guildId,
        reply: async (content: string) => {
          await message.reply(content)
        },
      })
    } catch (error) {
      Effect.logError(`Error handling @mention: ${error}`).pipe(
        Runtime.runSync(runtime)
      )
    }
  }
