import {
  type ChatInputCommandInteraction,
  type GuildMember,
  MessageFlags,
  SlashCommandBuilder,
  type User,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { buildLeaderboardEmbed } from '../embeds/leaderboard'
import { ApiService, MainLive } from '../services'
import type { ApiError, LeaderboardEntry } from '../services/api/client'
import { isChannelWhitelisted } from '../utils/permissions'

const API_TIMEOUT = 2000

export const data = new SlashCommandBuilder()
  .setName('leaderboard')
  .setDescription("View Teto's intimacy leaderboard for this server")

/**
 * Interface for user data maps
 */
interface UserDataMaps {
  membersMap: Map<string, GuildMember>
  usersMap: Map<string, User>
}

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
 * This replaces the Elixir Task.async/await pattern with Promise-based concurrency
 */
async function fetchUserDataConcurrently(
  interaction: ChatInputCommandInteraction,
  userIds: string[]
): Promise<UserDataMaps> {
  const guild = interaction.guild
  if (!guild) {
    throw new Error('Guild not available')
  }

  try {
    // Create promises for concurrent execution
    const memberPromise = guild.members.fetch({ limit: 1000 })
    const userPromises = userIds.map((userId) =>
      interaction.client.users.fetch(userId).catch((error) => {
        console.warn(`Failed to fetch user ${userId}:`, error)
        return null
      })
    )

    // Race against timeout - equivalent to Elixir's receive...after pattern
    const dataPromise = Promise.all([memberPromise, ...userPromises])
    const timeoutPromise =
      // biome-ignore lint/suspicious/noExplicitAny: <explanation>
      createTimeoutPromise<[any, ...(User | null)[]]>(API_TIMEOUT)

    const [members, ...users] = await Promise.race([
      dataPromise,
      timeoutPromise,
    ])

    // Build maps from the results - members is a Collection from Discord.js
    const membersMap = new Map<string, GuildMember>()
    for (const member of members.values()) {
      membersMap.set(member.user.id, member)
    }

    const usersMap = new Map<string, User>()
    for (const user of users) {
      if (user) {
        usersMap.set(user.id, user)
      }
    }

    return { membersMap, usersMap }
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
    const { membersMap, usersMap } = await fetchUserDataConcurrently(
      interaction,
      userIds
    )

    const leaderboardEmbed = buildLeaderboardEmbed(
      entries,
      membersMap,
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
  guildId: string
): Effect.Effect<LeaderboardEntry[], ApiError, ApiService> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

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

/**
 * Handle leaderboard command interaction using Effect
 */
async function handleLeaderboard(
  runtime: Runtime.Runtime<never>,
  interaction: ChatInputCommandInteraction,
  guildId: string
): Promise<void> {
  // Convert Effect to Either and run it
  const program = fetchLeaderboardEffect(guildId).pipe(
    Effect.either,
    Effect.provide(MainLive)
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

export async function execute(
  runtime: Runtime.Runtime<never>,
  interaction: ChatInputCommandInteraction
) {
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

  await handleLeaderboard(runtime, interaction, guildId)
}
