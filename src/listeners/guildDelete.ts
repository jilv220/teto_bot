import type { Guild } from 'discord.js'
import { Effect, Runtime } from 'effect'
import type { MainLive } from '../services'
import { guildApi } from '../services/api'

export const guildDeleteListener =
  (runtime: Runtime.Runtime<never>) => async (guild: Guild) => {
    await Runtime.runPromise(runtime)(
      guildApi
        .deleteGuildEffect(guild.id)
        .pipe(
          Effect.tap(({ data }) => Effect.logInfo(`Guild ${guild.id} left us!`))
        )
    )
  }
