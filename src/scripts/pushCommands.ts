import type {
  SlashCommandOptionsOnlyBuilder,
  SlashCommandSubcommandsOnlyBuilder,
} from 'discord.js'
import { REST, Routes } from 'discord.js'
import { Console, Effect, pipe } from 'effect'
import { appConfig } from '../services/config'

export const pushCommands = (
  commands: Array<
    SlashCommandSubcommandsOnlyBuilder | SlashCommandOptionsOnlyBuilder
  >
) => {
  const rest = new REST({ version: '10' })

  return pipe(
    appConfig,
    Effect.flatMap((config) => {
      rest.setToken(config.botToken)

      return Effect.tryPromise(() =>
        rest.put(
          Routes.applicationGuildCommands(config.clientId, config.devGuildId),
          {
            body: commands.map((command) => command.toJSON()),
          }
        )
      )
    }),
    Effect.matchEffect({
      onFailure: (err) => Console.error('put fail', err),
      onSuccess: () => Effect.void,
    })
  )
}
