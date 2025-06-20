import {
  type Awaitable,
  type CacheType,
  ChatInputCommandInteraction,
  type Interaction,
  InteractionResponse,
  MessageFlags,
} from 'discord.js'
import { Data, Effect, Runtime, pipe } from 'effect'
import type { MainLive } from '../services'

export class InteractionCreateError extends Data.TaggedError(
  'InteractionCreateError'
)<{
  message: unknown
}> {}

export const interactionCreateListener =
  (runtime: Runtime.Runtime<never>, live: typeof MainLive) =>
  async (interaction: Interaction<CacheType>): Promise<Awaitable<void>> => {
    if (!interaction.isChatInputCommand()) return

    const command = interaction.client.commands.get(interaction.commandName)
    if (!command) {
      Effect.logError(
        `No command matching ${interaction.commandName} was found.`
      ).pipe(Runtime.runSync(runtime))

      return
    }

    try {
      await command.execute(interaction)
    } catch (error) {
      Effect.logError(error).pipe(Runtime.runSync(runtime))

      if (interaction.replied || interaction.deferred) {
        await interaction.followUp({
          content: 'There was an error while executing this command!',
          flags: MessageFlags.Ephemeral,
        })
      } else {
        await interaction.reply({
          content: 'There was an error while executing this command!',
          flags: MessageFlags.Ephemeral,
        })
      }
    }
  }
