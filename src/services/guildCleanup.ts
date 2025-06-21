import type { Client } from 'discord.js'
import { Duration, Effect, Fiber, Schedule, pipe } from 'effect'
import { MainLive } from '.'
import { ApiError, ApiService } from '../services/api'

// Define error types for better error handling
export class GuildCleanupError extends Error {
  readonly _tag = 'GuildCleanupError'
  constructor(
    readonly message: string,
    readonly cause?: unknown
  ) {
    super(message)
  }
}

export class GuildDeleteError extends Error {
  readonly _tag = 'GuildDeleteError'
  constructor(
    readonly guildId: string,
    readonly message: string,
    readonly cause?: unknown
  ) {
    super(message)
  }
}

export interface CleanupResult {
  totalOrphaned: number
  successfullyRemoved: number
  failed: string[]
}

/**
 * Fetch all guilds from the database with proper error handling
 */
const fetchGuildsFromDatabase = Effect.gen(function* () {
  yield* Effect.logInfo('Fetching guilds from database...')
  const apiService = yield* ApiService
  const effectApi = apiService.effectApi

  const dbGuildsResponse = yield* effectApi.guilds.getGuilds()

  yield* Effect.logInfo(
    `Fetched ${dbGuildsResponse.data.guilds.length} guilds from database`
  )
  return dbGuildsResponse.data.guilds
})

/**
 * Delete a single orphaned guild with retry logic
 */
const deleteOrphanedGuild = (guildId: string) =>
  Effect.gen(function* () {
    yield* Effect.logInfo(`Attempting to delete orphaned guild: ${guildId}`)

    const apiService = yield* ApiService
    const effectApi = apiService.effectApi
    const deleteResponse = yield* effectApi.guilds.deleteGuild(guildId)
    yield* Effect.logInfo(`Successfully deleted orphaned guild: ${guildId}`)

    return guildId
  }).pipe(
    Effect.retry(
      Schedule.exponential(Duration.seconds(1)).pipe(
        Schedule.intersect(Schedule.recurs(3))
      )
    ),
    Effect.catchAll((error) =>
      Effect.gen(function* () {
        const errorMessage =
          error instanceof Error ? error.message : 'Unknown error'
        yield* Effect.logError(
          `Failed to delete guild ${guildId} after retries: ${errorMessage}`
        )
        return yield* Effect.fail(error)
      })
    )
  )

/**
 * Find and clean up orphaned guild records using Effect-ts patterns
 */
export const cleanupOrphanedGuilds = (client: Client) =>
  Effect.gen(function* () {
    yield* Effect.logInfo('Starting guild cleanup process...')

    // Fetch guilds from database
    const dbGuilds = yield* fetchGuildsFromDatabase

    // Get active guild IDs from Discord client
    const activeGuildIds = new Set(client.guilds.cache.keys())
    yield* Effect.logInfo(`Bot is currently in ${activeGuildIds.size} guilds`)

    // Find orphaned guilds
    const orphanedGuilds = dbGuilds.filter(
      (dbGuild) => !activeGuildIds.has(dbGuild.guildId)
    )

    if (orphanedGuilds.length === 0) {
      yield* Effect.logInfo('No orphaned guilds found')
      return {
        totalOrphaned: 0,
        successfullyRemoved: 0,
        failed: [] as string[],
      }
    }

    yield* Effect.logInfo(
      `Found ${orphanedGuilds.length} orphaned guilds, starting cleanup...`
    )

    // Process deletions with controlled concurrency and delays
    const deletionResults = yield* pipe(
      orphanedGuilds,
      (guilds) =>
        guilds.map((guild) =>
          deleteOrphanedGuild(guild.guildId).pipe(
            Effect.either,
            Effect.delay(Duration.millis(100)) // Rate limiting
          )
        ),
      (effects) => Effect.all(effects, { concurrency: 5 }) // Limit concurrent deletions
    )

    // Collect results
    const successful: string[] = []
    const failed: string[] = []

    for (const result of deletionResults) {
      if (result._tag === 'Right') {
        successful.push(result.right)
      } else {
        const error = result.left
        if (error instanceof ApiError) {
          failed.push(error.message)
        }
      }
    }

    const cleanupResult: CleanupResult = {
      totalOrphaned: orphanedGuilds.length,
      successfullyRemoved: successful.length,
      failed,
    }

    yield* Effect.logInfo(
      `Cleanup complete: ${cleanupResult.successfullyRemoved}/${cleanupResult.totalOrphaned} successful, ${cleanupResult.failed.length} failed`
    )

    return cleanupResult
  }).pipe(
    Effect.catchAll((error) =>
      Effect.gen(function* () {
        const errorMessage =
          error instanceof Error ? error.message : 'Unknown error'
        yield* Effect.logError(`Guild cleanup failed: ${errorMessage}`)
        return {
          totalOrphaned: 0,
          successfullyRemoved: 0,
          failed: [] as string[],
        }
      })
    )
  )

/**
 * Effect for running scheduled cleanup task
 */
const scheduleCleanupTask = (client: Client) =>
  Effect.gen(function* () {
    yield* Effect.logInfo('Running scheduled guild cleanup...')
    const result = yield* cleanupOrphanedGuilds(client)

    if (result.totalOrphaned > 0) {
      yield* Effect.logInfo(
        `Cleanup summary: ${result.successfullyRemoved}/${result.totalOrphaned} guilds cleaned, ${result.failed.length} failed`
      )
    }

    return result
  })

/**
 * Start background cleanup task using Effect Schedule
 * Returns an Effect that runs indefinitely and can be interrupted
 */
export const startGuildCleanupTask = (client: Client) =>
  Effect.gen(function* () {
    yield* Effect.logInfo('Starting guild cleanup task (runs every 2 hours)')

    // Run the cleanup task on a schedule indefinitely
    // Use schedule instead of repeat to skip first execution
    yield* scheduleCleanupTask(client).pipe(
      Effect.schedule(Schedule.fixed(Duration.hours(2)))
    )
  })

/**
 * Effect-based cleanup with comprehensive error handling and logging
 */
export const cleanupOrphanedGuildsEffect = (client: Client) =>
  cleanupOrphanedGuilds(client)
