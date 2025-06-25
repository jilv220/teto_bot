import { type AIMessageChunk, HumanMessage } from '@langchain/core/messages'
import {
  type Attachment,
  type ChatInputCommandInteraction,
  MessageFlags,
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
  .setDescription('Chat with Teto!')
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

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
): Promise<void> {
  const message = interaction.options.getString('message', true)
  const imageOption = interaction.options.getAttachment('image')

  // Check if user is in a guild
  if (!interaction.guildId) {
    await interaction.reply({
      content: 'This command can only be used in servers!',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Check if channel is whitelisted first
  const isChannelWhitelisted = await ChannelService.pipe(
    Effect.flatMap(({ isChannelWhitelisted }) =>
      isChannelWhitelisted(interaction.channelId)
    )
  ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

  if (!isChannelWhitelisted) {
    await interaction.reply({
      content: 'This channel is not whitelisted for Teto interactions!',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // RateLimit channel
  const rateLimitRes = ChannelRateLimiter.pipe(
    Effect.flatMap((limiter) =>
      Effect.all({
        isRateLimited: limiter.isRateLimited(interaction.channelId),
        timeUntilReset: limiter.getTimeUntilReset(interaction.channelId),
      })
    )
  ).pipe(Effect.provide(live), Runtime.runSync(runtime))

  // Send RateLimit Msg
  if (rateLimitRes.isRateLimited) {
    const secondsUntilReset = Math.ceil(rateLimitRes.timeUntilReset / 1000)
    await interaction.reply({
      content: `This channel is being rate limited. Please wait ${secondsUntilReset} seconds before sending another message.`,
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Defer reply, for llm reply can take more than 3 seconds in some cases
  await interaction.deferReply()

  try {
    // Record user message
    const userMsgRecordRes = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.recordUserMessage({
          userId: interaction.user.id,
          guildId: interaction.guildId || '',
          intimacyIncrement: 1,
        })
      )
    ).pipe(
      Effect.tap((resp) =>
        Effect.logInfo(
          `Recording message - User: ${interaction.user.username}(${interaction.user.id}) from (Guild: ${interaction.guildId})`
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
      await interaction.editReply({
        content: `You've run out of message credits! Vote for the bot to get more credits.\n${config.voteUrl}`,
      })
      return
    }

    // Check for prompt injection attempts
    if (containsInjection(message)) {
      Effect.logWarning(
        `Prompt injection detected from user ${interaction.user.username}(${interaction.user.id}) in guild ${interaction.guildId}: "${message}"`
      ).pipe(Runtime.runSync(runtime))

      const teasingResponse = await createLLMResponse(
        buildPromptInjectionMessage(),
        null,
        0, // Use intimacy level 0 for injection attempts
        interaction.user.username,
        interaction.channelId
      )
        .pipe(Effect.provide(live), Runtime.runPromise(runtime))
        .catch(() => {
          // Fallback to static message if LLM fails
          return {
            content: buildPromptInjectionFallbackMessage(),
          }
        })

      await interaction.editReply({
        content: String(teasingResponse.content),
      })
      return
    }

    // Get user intimacy for LLM context
    const intimacy =
      userMsgRecordRes._tag === 'Right'
        ? userMsgRecordRes.right.data.userGuild.intimacy
        : 0

    // Generate LLM response
    const response = await createLLMResponse(
      message,
      imageOption,
      intimacy,
      interaction.user.username,
      interaction.channelId
    ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

    await interaction.editReply({
      content: String(response.content),
    })
  } catch (error) {
    Effect.logError(`Error in chat command: ${error}`).pipe(
      Runtime.runSync(runtime)
    )

    try {
      await interaction.editReply({
        content:
          'Sorry, I encountered an error while processing your message. Please try again later.',
      })
    } catch (replyError) {
      Effect.logError(`Failed to send error reply: ${replyError}`).pipe(
        Runtime.runSync(runtime)
      )
    }
  }
}
