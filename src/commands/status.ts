import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { buildTetoStatusEmbed } from '../embeds/teto'
import { ApiService, ChannelService, type MainLive } from '../services'
import type { ApiError } from '../services/api/client'
import { hasVotedRecently } from '../services/voting'

export const data = new SlashCommandBuilder()
  .setName('status')
  .setDescription(
    'Check your intimacy level with Teto, relationship tier, feed status, and message credits'
  )

async function executeStatusCommand(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction,
  userId: string,
  guildId: string,
  channelId: string
) {
  await interaction.deferReply()

  try {
    // Check if channel is whitelisted
    const isChannelWhitelisted = await ChannelService.pipe(
      Effect.flatMap(({ isChannelWhitelisted }) =>
        isChannelWhitelisted(channelId)
      )
    ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

    if (!isChannelWhitelisted) {
      await interaction.editReply({
        content: 'This channel is not whitelisted for Teto interactions!',
      })
      return
    }

    // Fetch user data
    const userDataResult = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.ensureUserGuildExists({
          userId,
          guildId,
        })
      )
    ).pipe(Effect.either, Effect.provide(live), Runtime.runPromise(runtime))

    if (Either.isLeft(userDataResult)) {
      const error = userDataResult.left as ApiError
      if (error.statusCode === 404) {
        await interaction.editReply({
          content:
            'You have no interaction history with Teto in this server yet! Start chatting with `/chat` to build your relationship.',
        })
      } else {
        await interaction.editReply({
          content: 'Failed to retrieve your status. Please try again later.',
        })
      }
      return
    }

    const { data } = userDataResult.right
    const { user, userGuild } = data

    // Check vote status
    const hasVoted = hasVotedRecently(user.lastVotedAt)

    const userData = {
      username: interaction.user.username,
      avatarURL: interaction.user.displayAvatarURL({ extension: 'png' }),
    }

    const metrics = {
      intimacy: userGuild.intimacy,
      dailyMessageCount: Number.parseInt(userGuild.dailyMessageCount),
    }

    const status = {
      messageCredits: Number.parseInt(user.messageCredits),
      hasVoted,
    }

    const embed = buildTetoStatusEmbed(
      metrics,
      status,
      userGuild,
      userData,
      interaction.guild?.name
    )

    await interaction.editReply({
      embeds: [embed],
    })
  } catch (error) {
    console.error('Error in status command:', error)
    await interaction.editReply({
      content: 'An error occurred while retrieving your status.',
    })
  }
}

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
): Promise<void> {
  const userId = interaction.user.id
  const guildId = interaction.guildId
  const channelId = interaction.channelId

  if (!guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  await executeStatusCommand(
    runtime,
    live,
    interaction,
    userId,
    guildId,
    channelId
  )
}
