import { Client, GatewayIntentBits, Partials } from 'discord.js'
import type { Collection } from 'discord.js'
import { Context, Effect, Layer } from 'effect'
import { appConfig } from './config'

// Extend the Discord.js Client type to include commands property
declare module 'discord.js' {
  interface Client {
    commands: Collection<
      string,
      { data: { name: string }; execute: (...args: unknown[]) => unknown }
    >
  }
}

export class ClientContext extends Context.Tag('ClientContext')<
  ClientContext,
  Client<true>
>() {}

export const ClientLive = Layer.effect(
  ClientContext,
  Effect.gen(function* () {
    const config = yield* appConfig

    const client = new Client<true>({
      intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages],
    })

    yield* Effect.tryPromise(() => client.login(config.botToken))

    return client
  })
)
