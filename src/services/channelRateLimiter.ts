import { Context, Effect, Layer, Ref, Schedule } from 'effect'
import { appConfig } from './config'

interface RateLimitEntry {
  timestamps: number[]
  lastCleanup: number
}

interface RateLimitConfig {
  maxRequests: number
  windowMs: number
  cleanupIntervalMs?: number
}

const make = (config: RateLimitConfig) =>
  Effect.gen(function* () {
    const channels = yield* Ref.make(new Map<string, RateLimitEntry>())

    const rateLimitConfig: Required<RateLimitConfig> = {
      maxRequests: config.maxRequests,
      windowMs: config.windowMs,
      cleanupIntervalMs: config.cleanupIntervalMs ?? 300000, // 5 minutes default
    }

    const cleanup = Effect.gen(function* () {
      const channelsMap = yield* Ref.get(channels)
      const now = Date.now()
      const staleThreshold = now - rateLimitConfig.windowMs * 2
      const newChannelsMap = new Map<string, RateLimitEntry>()

      for (const [channelId, entry] of channelsMap.entries()) {
        // Skip channels that haven't been used recently
        if (entry.lastCleanup < staleThreshold) {
          continue
        }

        // Clean up old timestamps
        const windowStart = now - rateLimitConfig.windowMs
        const cleanedTimestamps = entry.timestamps.filter(
          (timestamp) => timestamp > windowStart
        )

        // Keep the channel if it has recent timestamps or recent activity
        if (
          cleanedTimestamps.length > 0 ||
          entry.lastCleanup >= staleThreshold
        ) {
          newChannelsMap.set(channelId, {
            ...entry,
            timestamps: cleanedTimestamps,
          })
        }
      }

      yield* Ref.set(channels, newChannelsMap)
      yield* Effect.logDebug(
        `Rate limiter cleanup completed. Active channels: ${newChannelsMap.size}`
      )
    })

    const isRateLimited = (channelId: string) =>
      Effect.gen(function* () {
        const now = Date.now()
        const channelsMap = yield* Ref.get(channels)
        const entry = channelsMap.get(channelId)

        if (!entry) {
          // First request for this channel
          const newEntry: RateLimitEntry = {
            timestamps: [now],
            lastCleanup: now,
          }
          const newChannelsMap = new Map(channelsMap)
          newChannelsMap.set(channelId, newEntry)
          yield* Ref.set(channels, newChannelsMap)
          return false
        }

        // Remove timestamps outside the window
        const windowStart = now - rateLimitConfig.windowMs
        const validTimestamps = entry.timestamps.filter(
          (timestamp) => timestamp > windowStart
        )

        // Check if we're at the limit
        if (validTimestamps.length >= rateLimitConfig.maxRequests) {
          return true
        }

        // Add current timestamp and update entry
        const updatedEntry: RateLimitEntry = {
          timestamps: [...validTimestamps, now],
          lastCleanup: now,
        }
        const newChannelsMap = new Map(channelsMap)
        newChannelsMap.set(channelId, updatedEntry)
        yield* Ref.set(channels, newChannelsMap)

        return false
      })

    const getRemainingRequests = (channelId: string) =>
      Effect.gen(function* () {
        const now = Date.now()
        const channelsMap = yield* Ref.get(channels)
        const entry = channelsMap.get(channelId)

        if (!entry) {
          return rateLimitConfig.maxRequests
        }

        const windowStart = now - rateLimitConfig.windowMs
        const validTimestamps = entry.timestamps.filter(
          (timestamp) => timestamp > windowStart
        )

        return Math.max(0, rateLimitConfig.maxRequests - validTimestamps.length)
      })

    const getTimeUntilReset = (channelId: string) =>
      Effect.gen(function* () {
        const channelsMap = yield* Ref.get(channels)
        const entry = channelsMap.get(channelId)

        if (!entry || entry.timestamps.length === 0) {
          return 0
        }

        const now = Date.now()
        const windowStart = now - rateLimitConfig.windowMs
        const validTimestamps = entry.timestamps.filter(
          (timestamp) => timestamp > windowStart
        )

        if (validTimestamps.length < rateLimitConfig.maxRequests) {
          return 0
        }
        5
        // Time until the oldest valid timestamp expires
        const oldestTimestamp = Math.min(...validTimestamps)
        return Math.max(0, oldestTimestamp + rateLimitConfig.windowMs - now)
      })

    const getStats = () =>
      Effect.gen(function* () {
        const channelsMap = yield* Ref.get(channels)
        let totalRequests = 0

        for (const entry of channelsMap.values()) {
          totalRequests += entry.timestamps.length
        }

        return {
          channelCount: channelsMap.size,
          totalRequests,
        }
      })

    const startCleanup = () =>
      Effect.gen(function* () {
        yield* Effect.logInfo('Starting rate limiter cleanup...')

        const schedule = Schedule.fixed(
          `${rateLimitConfig.cleanupIntervalMs} millis`
        )
        yield* cleanup.pipe(Effect.schedule(schedule))
      })

    return ChannelRateLimiter.of({
      isRateLimited: isRateLimited,
      getRemainingRequests: getRemainingRequests,
      getTimeUntilReset: getTimeUntilReset,
      getStats: getStats,
      startCleanup,
    })
  })

export class ChannelRateLimiter extends Context.Tag('ChannelRateLimiter')<
  ChannelRateLimiter,
  {
    isRateLimited: (channelId: string) => Effect.Effect<boolean>
    getRemainingRequests: (channelId: string) => Effect.Effect<number>
    getTimeUntilReset: (channelId: string) => Effect.Effect<number>
    getStats: () => Effect.Effect<{
      channelCount: number
      totalRequests: number
    }>
    startCleanup: () => Effect.Effect<void, never>
  }
>() {}

export const initChannelRateLimiter = (config: RateLimitConfig) =>
  Layer.effect(ChannelRateLimiter, make(config))

const config = Effect.runSync(appConfig)
export const ChannelRateLimiterLive = initChannelRateLimiter({
  maxRequests: config.maxRequests,
  windowMs: config.windowMs,
  cleanupIntervalMs: config.cleanupIntervalMs,
})
