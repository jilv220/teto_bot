import { HumanMessage } from '@langchain/core/messages'
import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { v4 as uuidv4 } from 'uuid'
import { ChannelService, type MainLive } from '../services'
import { effectApi } from '../services/api/client'
import { LLMConversationModelContext } from '../services/llm/model'
import {
  buildWordOfTheDayMessage,
  systemPromptEffect,
} from '../services/llm/prompt'

export const data = new SlashCommandBuilder()
  .setName('word')
  .setDescription('Get Teto Word of the Day!')

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  const guildId = interaction.guildId
  const channelId = interaction.channelId
  const username = interaction.user.username

  if (!guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Check if channel is whitelisted
  const isWhitelisted = await Effect.gen(function* () {
    const channelService = yield* ChannelService
    return yield* channelService.isChannelWhitelisted(channelId)
  }).pipe(Effect.provide(live), Runtime.runPromise(runtime))

  if (!isWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels. ',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const program = Effect.gen(function* () {
    // Get today's word
    const wordResponseRes = yield* effectApi.wordOfTheDay
      .getTodaysWord()
      .pipe(Effect.either)

    const word = Either.isRight(wordResponseRes)
      ? wordResponseRes.right.data.word
      : 'job'

    // Generate the message using LLM
    const systemPrompt = yield* systemPromptEffect
    const conversationModel = yield* LLMConversationModelContext

    const userMessage = new HumanMessage({
      id: uuidv4(),
      content: buildWordOfTheDayMessage(word),
    })

    const formattedPrompt = yield* Effect.promise(() =>
      systemPrompt.formatMessages({
        messages: [userMessage],
        username: username,
        intimacy: 201,
      })
    )

    const response = yield* Effect.promise(() =>
      conversationModel.invoke(formattedPrompt)
    )

    return response.content as string
  })

  const result = await Runtime.runPromise(runtime)(
    program.pipe(Effect.provide(live), Effect.either)
  )

  if (Either.isLeft(result)) {
    await interaction.reply({
      content:
        'Something went wrong while getting the word of the day. Please try again.',
      flags: MessageFlags.Ephemeral,
    })
  } else {
    await interaction.reply({ content: result.right })
  }
}
