import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import {
  ApiService,
  ChannelNotWhitelistedError,
  ChannelService,
  type MainLive,
} from '../services'
import type { ApiError } from '../services/api/client'
import {
  buildFeedCooldownMessage,
  buildFeedSuccessMessage,
  checkFeedCooldown,
} from '../services/feed'
import { FEED_INTIMACY_GAIN } from '../services/teto'

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
  guildId: string,
  channelId: string
): Effect.Effect<
  FeedResult,
  ApiError | ChannelNotWhitelistedError,
  ApiService | ChannelService
> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    const channelService = yield* ChannelService
    const isChannelWhitelisted =
      yield* channelService.isChannelWhitelisted(channelId)

    if (!isChannelWhitelisted) {
      return yield* Effect.fail(
        new ChannelNotWhitelistedError({
          message: 'This command can only be used in whitelisted channels.',
        })
      )
    }

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
    Effect.tapError((error) =>
      Effect.logError(
        `Failed to feed Teto for user ${userId} in guild ${guildId}: ${error.message}`
      )
    )
  )

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

  // Convert Effect to Either and run it
  const program = executeFeedEffect(userId, guildId, channelId).pipe(
    Effect.either,
    Effect.provide(live)
  )
  const result = await Runtime.runPromise(runtime)(program)

  // Handle Either result
  if (Either.isLeft(result)) {
    await interaction.reply({
      content: 'Something went wrong while feeding Teto. Please try again.',
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
