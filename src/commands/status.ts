import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { buildTetoStatusEmbed } from '../embeds/teto'
import { ApiService, ChannelService, type MainLive } from '../services'
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
        content: 'This command can only be used in whitelisted channels.',
      })
      return
    }

    // Fetch user data
    const userDataResult = await ApiService.pipe(
      Effect.flatMap(({ effectApi }) =>
        effectApi.discord.ensureUserGuildExists({
          userId,
          guildId: guildId,
        })
      )
    ).pipe(Effect.either, Effect.provide(live), Runtime.runPromise(runtime))

    if (Either.isLeft(userDataResult)) {
      // Can't be 404...
      await interaction.editReply({
        content: 'Failed to retrieve your status. Please try again later.',
      })
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

    const status = {
      messageCredits: Number.parseInt(user.messageCredits),
      hasVoted,
    }

    const maybeMetrics = userGuild
      ? {
          intimacy: userGuild.intimacy,
          dailyMessageCount: Number.parseInt(userGuild.dailyMessageCount),
        }
      : null

    const embed = buildTetoStatusEmbed(
      maybeMetrics,
      status,
      userGuild || null,
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
  // Only allow in guild channels
  if (!interaction.guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const userId = interaction.user.id
  const guildId = interaction.guildId
  const channelId = interaction.channelId

  await executeStatusCommand(
    runtime,
    live,
    interaction,
    userId,
    guildId,
    channelId
  )
}
