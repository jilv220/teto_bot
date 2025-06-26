import { type AIMessageChunk, HumanMessage } from '@langchain/core/messages'
import {
  type Attachment,
  type ChatInputCommandInteraction,
  SlashCommandBuilder,
} from 'discord.js'
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

export const data = new SlashCommandBuilder()
  .setName('teto')
  .setDescription('Chat with Teto in servers!')
  .addStringOption((option) =>
    option
      .setName('message')
      .setDescription('Your message to Teto')
      .setRequired(true)
  )
  .addAttachmentOption((option) =>
    option
      .setName('image')
      .setDescription('Optional image to share with Teto')
      .setRequired(false)
  )

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
 * Shared function to handle Teto interactions (used by both slash commands and DM messages)
 */
export const handleTetoInteraction = async (
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  options: {
    content: string
    imageAttachment?: Attachment | null
    userId: string
    username: string
    channelId: string
    guildId: string | null
    reply: (content: string) => Promise<void>
    deferReply?: () => Promise<void>
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
    deferReply,
  } = options
  const isDM = !guildId

  Effect.logInfo(
    `User: ${username}(${userId}) interacted with Teto through ${isDM ? 'DM' : 'server'}`
  ).pipe(Effect.provide(live), Runtime.runSync(runtime))

  // For guild interactions, check if channel is whitelisted
  if (!isDM) {
    const isChannelWhitelisted = await ChannelService.pipe(
      Effect.flatMap(({ isChannelWhitelisted }) =>
        isChannelWhitelisted(channelId)
      )
    ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

    if (!isChannelWhitelisted) {
      await reply('This channel is not whitelisted for Teto interactions!')
      return
    }
  }

  // RateLimit channel (works for both DMs and guild channels)
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

  // Defer reply if function is provided (for slash commands)
  if (deferReply) {
    await deferReply()
  }

  try {
    // Record user message (handle DMs with null guildId)
    const userMsgRecordRes = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.recordUserMessage({
          userId: userId,
          guildId: guildId || undefined,
          intimacyIncrement: 1,
        })
      )
    ).pipe(
      Effect.tap((resp) =>
        Effect.logInfo(
          `Recording message - User: ${username}(${userId}) from (${isDM ? 'DM' : `Guild: ${guildId}`})`
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
        `Prompt injection detected from user ${username}(${userId}) in ${isDM ? 'DM' : `guild ${guildId}`}: "${content}"`
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

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
): Promise<void> {
  const message = interaction.options.getString('message', true)
  const imageOption = interaction.options.getAttachment('image')

  await handleTetoInteraction(runtime, live, {
    content: message,
    imageAttachment: imageOption,
    userId: interaction.user.id,
    username: interaction.user.username,
    channelId: interaction.channelId,
    guildId: interaction.guildId,
    reply: async (content: string) => {
      await interaction.editReply({ content })
    },
    deferReply: async () => {
      await interaction.deferReply()
    },
  })
}
