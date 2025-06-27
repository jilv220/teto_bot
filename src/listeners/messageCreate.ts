import { type AIMessageChunk, HumanMessage } from '@langchain/core/messages'
import type { Attachment, Message } from 'discord.js'
import { PermissionFlagsBits } from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import {
  ApiService,
  ChannelNotWhitelistedError,
  ChannelService,
  type MainLive,
} from '../services'
import type { RecordUserMessageResponse } from '../services/api/client'
import { ChannelRateLimiter } from '../services/channelRateLimiter'
import { appConfig, isProduction } from '../services/config'
import { DiscordService } from '../services/discord'
import { LLMContext } from '../services/llm'
import { processImageAttachments } from '../services/llm/attachment'
import {
  buildPromptInjectionFallbackMessage,
  buildPromptInjectionMessage,
} from '../services/llm/prompt'
import { MessagesService } from '../services/messages'
import { containsInjection } from '../services/messages/filter'
import {
  canBotSendMessages,
  hasManageChannelsPermissionFromMessage,
} from '../utils/permissions'

const buildSetupMessage = () =>
  "This channel isn't set up for Teto yet! 🎵\n\n" +
  'To start using Teto here, someone with **Manage Channels** permission needs to mention me first.'

const createLLMResponse = (
  message: Message,
  content: string,
  intimacy: number
) =>
  Effect.gen(function* () {
    const llm = yield* LLMContext

    // Process any image attachments - filter for images here
    const attachments = Array.from(message.attachments.values())
    const imageAttachments = attachments.filter((att) =>
      att.contentType?.startsWith('image/')
    )
    const imageContent =
      imageAttachments.length > 0
        ? yield* processImageAttachments(imageAttachments)
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
      username: message.author.username,
      intimacy: intimacy,
    }

    // One thread per channel basically
    const config = { configurable: { thread_id: message.channelId } }

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
 * Handle messages - only respond to @mentions in guild channels
 */
export const messageCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (message: Message): Promise<void> => {
    const userId = message.author.id
    const username = message.author.username
    const channelId = message.channelId
    const guildId = message.guildId

    const removeBotMentionEffect = Effect.gen(function* () {
      const messagesService = yield* MessagesService
      const content = yield* messagesService.removeBotMention(message)
      yield* Effect.logInfo(
        `User: ${username}(${userId}) interacted with Teto via @mention in guild ${guildId}`
      )
      return content
    })

    const checkChannelWhitelistEffect = Effect.gen(function* () {
      const channelService = yield* ChannelService
      const isChannelWhitelisted =
        yield* channelService.isChannelWhitelisted(channelId)

      if (!isChannelWhitelisted) {
        yield* Effect.log(`Channel ${channelId} is not yet whitelisted`)
        // TODO: auto whitelist channel
        return false // Not whitelisted, should stop processing
      }

      return true // Whitelisted, continue processing
    })

    const checkRateLimitEffect = Effect.gen(function* () {
      const rateLimiter = yield* ChannelRateLimiter
      const { isRateLimited, timeUntilReset } = yield* Effect.all({
        isRateLimited: rateLimiter.isRateLimited(channelId),
        timeUntilReset: rateLimiter.getTimeUntilReset(channelId),
      })

      if (isRateLimited) {
        const secondsUntilReset = Math.ceil(timeUntilReset / 1000)
        const discordService = yield* DiscordService
        yield* discordService.reply(
          message,
          `This channel is being rate limited. Please wait ${secondsUntilReset} seconds before sending another message.`
        )
        return false // Rate limited, should stop processing
      }

      return true // Not rate limited, continue processing
    })

    const recordUserMessageEffect = ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.recordUserMessage({
          userId: userId,
          // biome-ignore lint/style/noNonNullAssertion: can't be null
          guildId: guildId!,
          intimacyIncrement: 1,
        })
      ),
      Effect.tap((resp) =>
        Effect.logInfo(
          `Recording message - User: ${username}(${userId}) from Guild: ${guildId}`
        )
      ),
      Effect.mapError((error) => {
        if (error.statusCode === 402) return 'not enough credit' as const
        return 'fail to record user message' as const
      }),
      Effect.either
    )

    const handleNotEnoughCreditEffect = (
      userMsgRecordRes: Either.Either<
        RecordUserMessageResponse,
        'not enough credit' | 'fail to record user message'
      >
    ) =>
      Effect.gen(function* () {
        const config = yield* appConfig
        if (
          isProduction &&
          Either.isLeft(userMsgRecordRes) &&
          userMsgRecordRes.left === 'not enough credit'
        ) {
          const discordService = yield* DiscordService
          yield* discordService.reply(
            message,
            `You've run out of message credits! Vote for the bot to get more credits.\n${config.voteUrl}`
          )
          return true // Indicate we should return early
        }
        return false
      })

    const handlePromptInjectionEffect = (content: string) =>
      Effect.gen(function* () {
        if (containsInjection(content)) {
          yield* Effect.logWarning(
            `Prompt injection detected from user ${username}(${userId}) in guild ${guildId}: "${content}"`
          )

          const teasingResponse = yield* createLLMResponse(
            message,
            buildPromptInjectionMessage(),
            0 // Use intimacy level 0 for injection attempts
          ).pipe(
            Effect.catchAll(() =>
              Effect.succeed({
                content: buildPromptInjectionFallbackMessage(),
              })
            )
          )

          const discordService = yield* DiscordService
          yield* discordService.reply(message, String(teasingResponse.content))
          return true // Indicate we should return early
        }
        return false
      })

    const handleNormalResponseEffect = (
      content: string,
      userMsgRecordRes: Either.Either<
        RecordUserMessageResponse,
        'not enough credit' | 'fail to record user message'
      >
    ) =>
      Effect.gen(function* () {
        // Get user intimacy for LLM context
        const intimacy =
          userMsgRecordRes._tag === 'Right'
            ? userMsgRecordRes.right.data?.userGuild?.intimacy || 0
            : 0

        // Generate LLM response
        const response = yield* createLLMResponse(message, content, intimacy)

        const discordService = yield* DiscordService
        yield* discordService.reply(message, String(response.content))
      })

    // Entry
    const mainEffect = Effect.gen(function* () {
      const content = yield* removeBotMentionEffect
      const channelService = yield* ChannelService

      const isWhitelisted = yield* checkChannelWhitelistEffect

      /**
       * Auto whitelist if user has manage channels permission and channel is not yet whitelisted
       */
      if (!isWhitelisted && hasManageChannelsPermissionFromMessage(message)) {
        // biome-ignore lint/style/noNonNullAssertion: can't be null
        yield* channelService.whitelistChannel(channelId, userId, guildId!)
        yield* Effect.logInfo(`Auto whitelist channel ${channelId}`)
      } else if (
        !isWhitelisted &&
        !hasManageChannelsPermissionFromMessage(message)
      ) {
        const discordService = yield* DiscordService
        yield* discordService.reply(message, buildSetupMessage())
        return
      }
      // the other two cases should just proceed

      const passedRateLimit = yield* checkRateLimitEffect
      if (!passedRateLimit) return

      const userMsgRecordRes = yield* recordUserMessageEffect

      const notEnoughCredit =
        yield* handleNotEnoughCreditEffect(userMsgRecordRes)
      if (notEnoughCredit) return

      const hasInjection = yield* handlePromptInjectionEffect(content)
      if (hasInjection) return

      yield* handleNormalResponseEffect(content, userMsgRecordRes)
    }).pipe(
      Effect.catchAll((error) =>
        Effect.gen(function* () {
          yield* Effect.logError(`Error in messageCreate mainEffect: ${error}`)

          const discordService = yield* DiscordService
          yield* discordService
            .reply(
              message,
              'Sorry, I encountered an error while processing your message. Please try again later.'
            )
            .pipe(
              Effect.catchAll((replyError) =>
                Effect.logError(`Failed to send error reply: ${replyError}`)
              )
            )
        })
      )
    )

    // Check if bot should respond to this message
    // includes all filtering logic
    if (!canBotSendMessages(message)) return

    await mainEffect.pipe(Effect.provide(live), Runtime.runPromise(runtime))
  }
