import { Context, Data, Effect, Layer } from 'effect'
import { ApiService, ApiServiceLive } from './api'

export class ChannelNotWhitelistedError extends Data.TaggedError(
  'ChannelNotWhitelistedError'
)<{
  message: unknown
}> {}

/**
 * Channel Service - handles channel-related operations
 */
export class ChannelService extends Context.Tag('ChannelService')<
  ChannelService,
  {
    isChannelWhitelisted: (channelId: string) => Effect.Effect<boolean, never>
    checkChannelAccess: (
      channelId: string,
      predicate: (channelId: string) => boolean
    ) => Effect.Effect<boolean, never>
  }
>() {}

const make = Effect.gen(function* () {
  const apiService = yield* ApiService

  return ChannelService.of({
    isChannelWhitelisted: (channelId: string) =>
      apiService.effectApi.channels.getChannel(channelId).pipe(
        Effect.map(() => true),
        Effect.catchAll(() => Effect.succeed(false))
      ),
    checkChannelAccess: (
      channelId: string,
      predicate: (channelId: string) => boolean
    ) =>
      Effect.gen(function* () {
        // Check special case first (e.g., DM channels)
        if (predicate(channelId)) {
          return true
        }
        // Otherwise check if channel is whitelisted
        return yield* apiService.effectApi.channels.getChannel(channelId).pipe(
          Effect.map(() => true),
          Effect.catchAll(() => Effect.succeed(false))
        )
      }),
  })
})

/**
 * Channel Service Implementation (requires ApiService)
 */
export const ChannelServiceLive = Layer.effect(ChannelService, make).pipe(
  Layer.provide(ApiServiceLive)
)
