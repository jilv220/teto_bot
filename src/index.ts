import { BunRuntime } from '@effect/platform-bun'
import { Collection } from 'discord.js'
import { Effect, Layer, Runtime } from 'effect'
import { AutoPoster } from 'topgg-autoposter'
import {
  interactionCreateListener,
  messageCreateListener,
  ready,
} from './listeners'
import { guildCreateListener } from './listeners/guildCreate'
import { guildDeleteListener } from './listeners/guildDelete'
import { MainLive } from './services'
import { ChannelRateLimiter } from './services/channelRateLimiter'
import { ClientContext } from './services/client'
import { startGuildCleanupTask } from './services/guildCleanup'

import * as fs from 'node:fs'
import * as path from 'node:path'
import { appConfig } from './services/config'

const loadCommandFiles = Effect.gen(function* () {
  const client = yield* ClientContext
  client.commands = new Collection()

  const commandsPath = path.join(__dirname, 'commands')

  // Function to recursively find command files
  const findCommandFiles = (dirPath: string): string[] => {
    const commandFiles: string[] = []
    const items = fs.readdirSync(dirPath, { withFileTypes: true })

    for (const item of items) {
      const itemPath = path.join(dirPath, item.name)

      if (item.isDirectory()) {
        commandFiles.push(...findCommandFiles(itemPath))
      } else if (
        item.isFile() &&
        (item.name.endsWith('.js') || item.name.endsWith('.ts'))
      ) {
        commandFiles.push(itemPath)
      }
    }

    return commandFiles
  }

  const commandFiles = findCommandFiles(commandsPath)

  // Load all command files
  for (const filePath of commandFiles) {
    const command = yield* Effect.tryPromise(() => import(filePath))

    if ('data' in command && 'execute' in command) {
      client.commands.set(command.data.name, command)
      yield* Effect.logInfo(`Loaded command: ${command.data.name}`)
    } else {
      yield* Effect.logWarning(
        `[WARNING] The command at ${filePath} is missing a required "data" or "execute" property.`
      )
    }
  }

  yield* Effect.logInfo(`Loaded ${client.commands.size} commands total`)
})

const program = Effect.scoped(
  Layer.memoize(MainLive).pipe(
    Effect.flatMap((mainLive) =>
      Effect.gen(function* () {
        yield* Effect.logInfo('Starting Discord bot...')
        // Load commands
        yield* loadCommandFiles

        const client = yield* ClientContext
        const config = yield* appConfig
        const poster = AutoPoster(config.topggToken, client)

        const channelRateLimiter = yield* ChannelRateLimiter

        // Create a runtime with the logger for the listeners
        // This is useful for integration with legacy code that must call back into Effect code.
        const runtime = yield* Effect.runtime()

        // Set up Discord client event listeners
        client
          .on('ready', ready(runtime))
          .on('guildCreate', guildCreateListener(runtime, mainLive))
          .on('guildDelete', guildDeleteListener(runtime, mainLive))
          .on('messageCreate', messageCreateListener(runtime, mainLive))
          .on('interactionCreate', interactionCreateListener(runtime, mainLive))

        // Set up autoposter listeners
        poster.on('posted', (stats) => {
          Effect.logInfo(
            `Posted stats to Top.gg | ${stats.serverCount} servers`
          ).pipe(Runtime.runSync(runtime))
        })

        // Start background cleanup fibers
        yield* startGuildCleanupTask(client).pipe(Effect.fork)
        yield* channelRateLimiter.startCleanup().pipe(Effect.fork)

        yield* Effect.logInfo('Bot startup completed successfully')
        yield* Effect.never
      }).pipe(Effect.provide(mainLive))
    )
  )
)

BunRuntime.runMain(program)
