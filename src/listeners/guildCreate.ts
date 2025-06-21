import type { Guild } from 'discord.js'
import { Duration, Effect, Runtime, Schedule } from 'effect'
import { ApiService, type MainLive } from '../services'

export const guildCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (guild: Guild) => {
    const program = ApiService.pipe(
      Effect.flatMap(({ effectApi }) => {
        return effectApi.guilds.createGuild({ guildId: guild.id })
      }),
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
    ).pipe(Effect.either)

    program.pipe(Effect.provide(live), Runtime.runPromise(runtime))
  }
