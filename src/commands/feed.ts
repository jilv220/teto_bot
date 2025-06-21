import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { ApiService, type MainLive } from '../services'
import { type ApiError, effectApi } from '../services/api/client'
import {
  buildFeedCooldownMessage,
  buildFeedSuccessMessage,
  checkFeedCooldown,
} from '../services/feed'
import { FEED_INTIMACY_GAIN } from '../services/teto'
import { isChannelWhitelisted } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('feed')
  .setDescription('Feed Teto to increase your intimacy with her')

type FeedResult =
  | { type: 'cooldown'; message: string }
  | { type: 'success'; message: string }

/**
 * Effect-based feed operation
 */
const executeFeedEffect = (
  userId: string,
  guildId: string
): Effect.Effect<FeedResult, ApiError, ApiService> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    // First ensure user exists and get current user guild data
    const ensureResult = yield* effectApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    const userGuild = ensureResult.data.userGuild

    // Check feed cooldown
    const cooldownCheck = checkFeedCooldown(userGuild.lastFeed)
    if (!cooldownCheck.allowed) {
      // Return cooldown message as a "success" since it's expected behavior
      return {
        type: 'cooldown' as const,
        message: buildFeedCooldownMessage(cooldownCheck.timeLeft),
      }
    }

    // Update intimacy and last feed time
    const newIntimacy = userGuild.intimacy + FEED_INTIMACY_GAIN
    const updateResult = yield* effectApi.userGuilds.updateUserGuild(
      userId,
      guildId,
      {
        intimacy: newIntimacy,
        lastFeed: new Date().toISOString(),
      }
    )

    // Success!
    return {
      type: 'success' as const,
      message: buildFeedSuccessMessage(updateResult.data.userGuild.intimacy),
    }
  }).pipe(
    Effect.tapError((error: ApiError) =>
      Effect.logError(
        `Failed to feed Teto for user ${userId} in guild ${guildId}: ${error.message}`
      )
    )
  )

/**
 * Build error message for feed failures
 */
function buildFeedErrorMessage(error: ApiError): string {
  return 'Something went wrong while feeding Teto. Please try again.'
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

  // Check if channel is whitelisted
  const isWhitelisted = await isChannelWhitelisted(channelId)
  if (!isWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Convert Effect to Either and run it
  const program = executeFeedEffect(userId, guildId).pipe(
    Effect.either,
    Effect.provide(live)
  )
  const result = await Runtime.runPromise(runtime)(program)

  // Handle Either result
  if (Either.isLeft(result)) {
    // Error case
    const errorMessage = buildFeedErrorMessage(result.left)
    await interaction.reply({
      content: errorMessage,
      flags: MessageFlags.Ephemeral,
    })
  } else {
    // Success case - handle both success and cooldown
    const feedResult = result.right
    await interaction.reply({
      content: feedResult.message,
    })
  }
}
