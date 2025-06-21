import type { Guild } from 'discord.js'
import { Effect, Runtime } from 'effect'
import { ApiService, type MainLive } from '../services'

export const guildDeleteListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (guild: Guild) => {
    const program = ApiService.pipe(
      Effect.flatMap(({ effectApi }) => {
        return effectApi.guilds.deleteGuild(guild.id)
      }),
      Effect.tap(() => Effect.logInfo(`Guild ${guild.id} left us!`)),
      Effect.tapError((error) =>
        Effect.logError(`Failed to delete guild ${guild.id}: ${error}`)
      )
    ).pipe(Effect.either)

    await Runtime.runPromise(runtime)(program.pipe(Effect.provide(live)))
  }
