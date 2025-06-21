import {
  type ChatInputCommandInteraction,
  SlashCommandBuilder,
} from 'discord.js'
import type { Runtime } from 'effect'
import type { MainLive } from '../services'

export const data = new SlashCommandBuilder()
  .setName('ping')
  .setDescription('Check if the bot is alive')

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  await interaction.reply('pong')
}
