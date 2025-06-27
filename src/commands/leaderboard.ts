import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
  type User,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { buildLeaderboardEmbed } from '../embeds/leaderboard'
import { ApiService, ChannelService, type MainLive } from '../services'
import type { ApiError, LeaderboardEntry } from '../services/api/client'

const API_TIMEOUT = 2000

export const data = new SlashCommandBuilder()
  .setName('leaderboard')
  .setDescription("View Teto's intimacy leaderboard for this server")

/**
 * Create a promise that rejects after a timeout
 */
function createTimeoutPromise<T>(timeoutMs: number): Promise<T> {
  return new Promise((_, reject) => {
    setTimeout(() => reject(new Error('Timeout')), timeoutMs)
  })
}

/**
 * Fetch user data from Discord API with timeout handling
 * Refactored to avoid guild_members intent by only fetching user data
 */
async function fetchUserDataConcurrently(
  interaction: ChatInputCommandInteraction,
  userIds: string[]
): Promise<Map<string, User>> {
  try {
    // Only fetch user data, no guild members
    const userPromises = userIds.map((userId) =>
      interaction.client.users.fetch(userId).catch((error) => {
        console.warn(`Failed to fetch user ${userId}:`, error)
        return null
      })
    )

    // Race against timeout
    const dataPromise = Promise.all(userPromises)
    const timeoutPromise = createTimeoutPromise<(User | null)[]>(API_TIMEOUT)

    const users = await Promise.race([dataPromise, timeoutPromise])

    // Build map from the results
    const usersMap = new Map<string, User>()
    for (const user of users) {
      if (user) {
        usersMap.set(user.id, user)
      }
    }

    return usersMap
  } catch (error) {
    if (error instanceof Error && error.message === 'Timeout') {
      throw new Error('TIMEOUT')
    }
    throw error
  }
}

/**
 * Build and send leaderboard with concurrent user data fetching
 */
async function buildAndSendLeaderboard(
  interaction: ChatInputCommandInteraction,
  entries: LeaderboardEntry[]
): Promise<void> {
  const userIds = entries.map((entry) => entry.userId)

  try {
    const usersMap = await fetchUserDataConcurrently(interaction, userIds)

    const leaderboardEmbed = buildLeaderboardEmbed(
      entries,
      usersMap,
      interaction.guild?.name
    )

    await interaction.reply({
      embeds: [leaderboardEmbed],
    })
  } catch (error) {
    console.error('Failed to fetch user data for leaderboard:', error)

    if (error instanceof Error && error.message === 'TIMEOUT') {
      await interaction.reply({
        content:
          'The leaderboard is temporarily unavailable due to slow Discord API response. Please try again later.',
        flags: MessageFlags.Ephemeral,
      })
    } else {
      await interaction.reply({
        content: 'Failed to retrieve the leaderboard. Please try again later.',
        flags: MessageFlags.Ephemeral,
      })
    }
  }
}

/**
 * Effect-based leaderboard operation
 */
const fetchLeaderboardEffect = (
  guildId: string,
  userId: string
): Effect.Effect<LeaderboardEntry[], ApiError, ApiService> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    // Ensure the guild and user exist in the database first
    // This handles cases where the guild creation failed or the user is new
    yield* effectApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    const result = yield* effectApi.leaderboard.getIntimacyLeaderboard({
      guildId,
      limit: 10,
    })

    return result.data.leaderboard
  }).pipe(
    Effect.tapError((error) =>
      Effect.logError(
        `Failed to fetch leaderboard for guild ${guildId}: ${error.message}`
      )
    )
  )

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  const guildId = interaction.guildId
  const channelId = interaction.channelId
  const userId = interaction.user.id

  if (!guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const isChannelWhitelisted = await ChannelService.pipe(
    Effect.flatMap(({ isChannelWhitelisted }) =>
      isChannelWhitelisted(channelId)
    )
  ).pipe(Effect.provide(live), Runtime.runPromise(runtime))

  if (!isChannelWhitelisted) {
    await interaction.reply({
      content: 'This command can only be used in whitelisted channels.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Convert Effect to Either and run it
  const program = fetchLeaderboardEffect(guildId, userId).pipe(
    Effect.either,
    Effect.provide(live)
  )
  const result = await Runtime.runPromise(runtime)(program)

  // Handle Either result
  if (Either.isLeft(result)) {
    // Error case
    await interaction.reply({
      content: 'Failed to retrieve the leaderboard. Please try again later.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const entries = result.right

  if (entries.length === 0) {
    await interaction.reply({
      content: 'No one has earned intimacy with Teto in this guild yet!',
    })
    return
  }

  await buildAndSendLeaderboard(interaction, entries)
}
