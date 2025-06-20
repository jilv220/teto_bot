import { ActivityType, type Client } from 'discord.js'
import { Effect, Runtime } from 'effect'
import type { MainLive } from '../services'

export const ready =
  (runtime: Runtime.Runtime<never>) => (client: Client<true>) => {
    Effect.logInfo('ws ready').pipe(Runtime.runSync(runtime))

    client.user.setActivity('Kasane Territory', { type: ActivityType.Playing })
  }
