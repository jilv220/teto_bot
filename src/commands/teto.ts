import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import {
  type DiscordUserData,
  type UserMetrics,
  type UserStatus,
  buildTetoStatusEmbed,
} from '../embeds/teto'
import { ApiService, type MainLive } from '../services'
import type { ApiError } from '../services/api/client'
import { hasVotedRecently } from '../services/voting'
import { isChannelWhitelisted } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('teto')
  .setDescription(
    'Check your intimacy level with Teto, relationship tier, feed status, and message credits'
  )

type TetoResult = {
  metrics: UserMetrics
  status: UserStatus
  lastFeed: string | undefined
}

/**
 * Effect-based teto operation
 */
const fetchTetoDataEffect = (
  userId: string,
  guildId: string
): Effect.Effect<TetoResult, ApiError, ApiService> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    // Ensure user exists and get user guild data
    const { data } = yield* effectApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    const user = data.user
    const userGuild = data.userGuild

    // Extract metrics and status
    const metrics: UserMetrics = {
      intimacy: userGuild.intimacy,
      dailyMessageCount: Number.parseInt(userGuild.dailyMessageCount),
    }

    const status: UserStatus = {
      messageCredits: Number.parseInt(user.messageCredits),
      hasVoted: hasVotedRecently(user.lastVotedAt),
    }

    return {
      metrics,
      status,
      lastFeed: userGuild.lastFeed,
    }
  }).pipe(
    Effect.tapError((error) =>
      Effect.logError(
        `Failed to fetch teto data for user ${userId} in guild ${guildId}: ${error.message}`
      )
    )
  )

/**
 * Execute the teto command with Effect-based API
 */
async function executeTetoCommand(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction,
  userId: string,
  guildId: string
): Promise<void> {
  // Convert Effect to Either and run it
  const program = fetchTetoDataEffect(userId, guildId).pipe(
    Effect.either,
    Effect.provide(live)
  )
  const result = await Runtime.runPromise(runtime)(program)

  // Handle Either result
  if (Either.isLeft(result)) {
    // Error case
    await interaction.reply({
      content: 'Something went wrong. Please try again later.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const { metrics, status, lastFeed } = result.right

  // Build user data for embed
  const userData: DiscordUserData = {
    username: interaction.user.username,
    avatarURL: interaction.user.displayAvatarURL(),
  }

  // Build and send embed response
  const embed = buildTetoStatusEmbed(
    metrics,
    status,
    { lastFeed },
    userData,
    interaction.guild?.name
  )

  await interaction.reply({
    embeds: [embed],
    flags: MessageFlags.Ephemeral,
  })
}

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
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

  const isWhitelisted = await isChannelWhitelisted(channelId)
  if (!isWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  await executeTetoCommand(runtime, live, interaction, userId, guildId)
}
