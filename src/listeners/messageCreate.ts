import { type AIMessageChunk, HumanMessage } from '@langchain/core/messages'
import type { Message } from 'discord.js'
import { Effect, Either, Match, Option, Runtime, pipe } from 'effect'
import { ApiService, ChannelService, type MainLive } from '../services'
import { ChannelRateLimiter } from '../services/channelRateLimiter'
import { appConfig, isProduction } from '../services/config'
import { safeReply } from '../services/discord'
import { LLMContext } from '../services/llm'
import { processImageAttachments } from '../services/llm/attachment'
import {
  buildPromptInjectionFallbackMessage,
  buildPromptInjectionMessage,
} from '../services/llm/prompt'
import { containsInjection } from '../services/messages/filter'
import { canBotSendMessages } from '../utils/permissions'

const createLLMResponse = (msg: Message<boolean>, intimacy: number) =>
  Effect.gen(function* () {
    const llm = yield* LLMContext

    // Process any image attachments
    const imageContent = yield* processImageAttachments(
      Array.from(msg.attachments.values())
    )
    const hasImages = imageContent.length > 0

    // Create message content - either just text or multimodal
    const messageContent = hasImages
      ? [
          {
            type: 'text' as const,
            text: msg.content || '',
          },
          // Only support 1 image for now to save cost...
          imageContent[0],
        ]
      : msg.content

    // Create simplified user context with just username and intimacy level
    const userContext = {
      username: msg.author.username,
      intimacy: intimacy,
    }

    // One thread per channel basically
    const config = { configurable: { thread_id: msg.channelId } }
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

export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (msg: Message<boolean>) => {
    // Ignore bot messages
    if (msg.author.bot) return

    // Ignore user not in a guild
    if (!msg.guildId) {
      Effect.logWarning(
        `Skipping message recording: ${msg.author.id} not in a guild`
      ).pipe(Runtime.runSync(runtime))
      return
    }

    // Check if channel is whitelisted first
    const isChannelWhitelisted = await ChannelService.pipe(
      Effect.flatMap(({ isChannelWhitelisted }) =>
        isChannelWhitelisted(msg.channelId)
      )
    ).pipe(Effect.provide(live), Runtime.runPromise(runtime))
    if (!isChannelWhitelisted) return

    // Check if bot has permission to send messages in this channel
    if (!canBotSendMessages(msg)) {
      Effect.logWarning(
        `Bot lacks permission to send messages in channel ${msg.channelId} in guild ${msg.guildId}`
      ).pipe(Runtime.runSync(runtime))
      return
    }

    const maybeMessageId = (messageId: string | undefined) =>
      messageId ? Option.some(messageId) : Option.none()

    const fetchReferencedMessage = (messageId: string) =>
      Effect.tryPromise({
        try: () => msg.channel.messages.fetch(messageId),
        catch: (error) => Effect.fail(error),
      }).pipe(
        Effect.tapError((error) =>
          Effect.logWarning('Could not fetch referenced message', error)
        ),
        Effect.catchAll(() => Effect.succeed(null))
      )

    // Ignore when user replies to another user
    const referencedMessage = await Runtime.runPromise(runtime)(
      pipe(
        maybeMessageId(msg.reference?.messageId),
        Option.match({
          onNone: () => Effect.succeed(null),
          onSome: fetchReferencedMessage,
        })
      )
    )
    if (referencedMessage && !referencedMessage.author.bot) return

    // RateLimit channel
    const rateLimitRes = ChannelRateLimiter.pipe(
      Effect.flatMap((limiter) =>
        Effect.all({
          isRateLimited: limiter.isRateLimited(msg.channelId),
          timeUntilReset: limiter.getTimeUntilReset(msg.channelId),
        })
      )
    ).pipe(Effect.provide(live), Runtime.runSync(runtime))

    // Send RateLimit Msg
    if (rateLimitRes.isRateLimited) {
      const secondsUntilReset = Math.ceil(rateLimitRes.timeUntilReset / 1000)
      await safeReply(
        msg,
        `This channel is being rate limited. Please wait ${secondsUntilReset} seconds before sending another message.`,
        runtime
      )
      return
    }

    // Record user message
    const userMsgRecordRes = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.recordUserMessage({
          userId: msg.author.id,
          // biome-ignore lint/style/noNonNullAssertion: Couldn't be null, ts is stupid here
          guildId: msg.guildId!,
          intimacyIncrement: 1,
        })
      )
    ).pipe(
      Effect.tap((resp) =>
        Effect.logInfo(
          `Recording message - User: ${msg.author.username}(${msg.author.id}) from (Guild: ${msg.guildId})`
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
      userMsgRecordRes._tag === 'Left' &&
      userMsgRecordRes.left === 'not enough credit'
    ) {
      await safeReply(
        msg,
        `You've run out of message credits! Vote for the bot to get more credits.\n${config.voteUrl}`,
        runtime
      )
      return
    }

    // Check for prompt injection attempts
    if (containsInjection(msg.content)) {
      Effect.logWarning(
        `Prompt injection detected from user ${msg.author.username}(${msg.author.id}) in guild ${msg.guildId}: "${msg.content}"`
      ).pipe(Runtime.runSync(runtime))

      const teasingResponse = await createLLMResponse(
        {
          ...msg,
          content: buildPromptInjectionMessage(),
        } as Message<boolean>,
        0 // Use intimacy level 0 for injection attempts
      )
        .pipe(Effect.provide(live), Runtime.runPromise(runtime))
        .catch(() => {
          // Fallback to static message if LLM fails
          return {
            content: buildPromptInjectionFallbackMessage(),
          }
        })

      await safeReply(msg, teasingResponse.content.toString(), runtime)
      return
    }

    /**
     * Get intimacy level from the user record response
     * Intimacy level will be zero in development
     */
    const intimacy = Either.isRight(userMsgRecordRes)
      ? userMsgRecordRes.right.data.userGuild.intimacy
      : 0

    // Send LLM Response
    createLLMResponse(msg, intimacy)
      .pipe(Effect.provide(live), Runtime.runPromise(runtime))
      .then(async (result) => {
        await safeReply(msg, result.content.toString(), runtime)
      })
      .catch((error) =>
        Effect.logError(`Failed to create LLM response: ${error}`).pipe(
          Runtime.runSync(runtime)
        )
      )
  }
