import type { Guild } from 'discord.js'
import { Duration, Effect, Runtime, Schedule } from 'effect'
import { guildApi } from '../services/api'

export const guildCreateListener =
  (runtime: Runtime.Runtime<never>) => async (guild: Guild) => {
    await Runtime.runPromise(runtime)(
      // Best effort try to join the bot to a guild, can still desync with actual server numbers
      guildApi
        .createGuildEffect({ guildId: guild.id })
        .pipe(
          Effect.tap(() =>
            Effect.logInfo(
              `Bot joined new guild: ${guild.name} (${guild.id}) with ${guild.memberCount} members`
            )
          ),
          Effect.tapError((error) =>
            Effect.logError(`Bot failed to join new guild: ${error}`)
          ),
          Effect.retry({
            schedule: Schedule.exponential(Duration.millis(100)).pipe(
              Schedule.jittered
            ),
            times: 3,
          })
        )
    )
  }
