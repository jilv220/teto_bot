import type { Guild } from 'discord.js'
import { Effect, Runtime } from 'effect'

export const guildCreateListener =
  (runtime: Runtime.Runtime<never>) => async (guild: Guild) => {
    // Only needs to log bot join, since we lazily insert guild data with ensureUserGuildExsits
    await Runtime.runPromise(runtime)(
      Effect.logInfo(
        `Bot joined new guild: ${guild.name} (${guild.id}) with ${guild.memberCount} members`
      )
    )
  }
