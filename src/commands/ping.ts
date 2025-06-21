import {
  type ChatInputCommandInteraction,
  SlashCommandBuilder,
} from 'discord.js'
import type { Runtime } from 'effect'

export const data = new SlashCommandBuilder()
  .setName('ping')
  .setDescription('Check if the bot is alive')

export async function execute(
  runtime: Runtime.Runtime<never>,
  interaction: ChatInputCommandInteraction
) {
  await interaction.reply('pong')
}
