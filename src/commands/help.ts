import {
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import type { Runtime } from 'effect'
import { type CommandInfo, buildHelpEmbed } from '../embeds/help'
import type { MainLive } from '../services'

export const data = new SlashCommandBuilder()
  .setName('help')
  .setDescription('Display information about TetoBot and its commands')

/**
 * Get all available commands from the client's command collection
 */
function getAvailableCommands(
  interaction: ChatInputCommandInteraction
): CommandInfo[] {
  const commands: CommandInfo[] = []

  // Get commands from the client's command collection
  for (const [_, command] of interaction.client.commands) {
    const commandData = command.data

    // Extract options if they exist
    const options: string[] = []
    if ('options' in commandData && Array.isArray(commandData.options)) {
      for (const option of commandData.options) {
        if ('name' in option && typeof option.name === 'string') {
          options.push(option.name)
        }
      }
    }

    commands.push({
      name: commandData.name,
      description:
        'description' in commandData &&
        typeof commandData.description === 'string'
          ? commandData.description
          : 'No description available',
      options: options.length > 0 ? options : undefined,
    })
  }

  // Sort commands alphabetically
  return commands.sort((a, b) => a.name.localeCompare(b.name))
}

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  try {
    const commands = getAvailableCommands(interaction)
    const helpEmbed = buildHelpEmbed(commands)

    await interaction.reply({
      embeds: [helpEmbed],
      flags: MessageFlags.Ephemeral,
    })
  } catch (error) {
    console.error('Failed to execute help command:', error)
    await interaction.reply({
      content:
        'Something went wrong while displaying help. Please try again later.',
      flags: MessageFlags.Ephemeral,
    })
  }
}
