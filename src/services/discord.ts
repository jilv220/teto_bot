/**
 * Discord related services
 */

import { type Message, RESTJSONErrorCodes } from 'discord.js'
import { Context, Data, Effect, Layer } from 'effect'

export class DiscordMessageError extends Data.TaggedError(
  'DiscordMessageError'
)<{
  code?: number
  message: string
  channelId?: string
  guildId?: string | null
}> {}

export interface DiscordService {
  /**
   * Safely reply to a Discord message with proper error handling for permission issues
   */
  readonly reply: (
    message: Message,
    content: string
  ) => Effect.Effect<boolean, DiscordMessageError>
}

export const DiscordService =
  Context.GenericTag<DiscordService>('DiscordService')

const make: Effect.Effect<DiscordService> = Effect.gen(function* () {
  const reply = (
    message: Message,
    content: string
  ): Effect.Effect<boolean, DiscordMessageError> =>
    Effect.gen(function* () {
      yield* Effect.logDebug(
        `Attempting to reply to message in channel ${message.channelId}`
      )

      return yield* Effect.tryPromise({
        try: () => message.reply(content),
        catch: (error) => {
          const discordError = error as { code?: number; message?: string }

          if (discordError.code === RESTJSONErrorCodes.MissingPermissions) {
            return new DiscordMessageError({
              code: discordError.code,
              message: `Missing permissions to send message in channel ${message.channelId}`,
              channelId: message.channelId,
              guildId: message.guildId,
            })
          }

          if (discordError.code === RESTJSONErrorCodes.MissingAccess) {
            return new DiscordMessageError({
              code: discordError.code,
              message: `Missing access to channel ${message.channelId}`,
              channelId: message.channelId,
              guildId: message.guildId,
            })
          }

          if (discordError.code === RESTJSONErrorCodes.UnknownChannel) {
            return new DiscordMessageError({
              code: discordError.code,
              message: `Unknown channel ${message.channelId}`,
              channelId: message.channelId,
              guildId: message.guildId,
            })
          }

          return new DiscordMessageError({
            code: discordError.code,
            message: `Failed to send message reply: ${discordError.message || String(error)}`,
            channelId: message.channelId,
            guildId: message.guildId,
          })
        },
      }).pipe(
        Effect.tap(() =>
          Effect.logDebug(
            `Successfully replied to message in channel ${message.channelId}`
          )
        ),
        Effect.map(() => true),
        Effect.catchAll((error) =>
          Effect.gen(function* () {
            if (
              error.code === 50013 ||
              error.code === 50001 ||
              error.code === 10003
            ) {
              yield* Effect.logWarning(error.message)
            } else {
              yield* Effect.logError(error.message)
            }
            return false
          })
        )
      )
    })

  return DiscordService.of({
    reply,
  })
})

export const DiscordServiceLive = Layer.effect(DiscordService, make)
