import { EmbedBuilder } from 'discord.js'
import { TETO_COLOR_SV } from './index'

export interface CommandInfo {
  name: string
  description: string
  options?: string[]
}

/**
 * Build help embed showing bot information and available commands
 */
export function buildHelpEmbed(commands: CommandInfo[]): EmbedBuilder {
  const commandList = commands
    .map((cmd) => {
      const options = cmd.options?.length
        ? ` ${cmd.options.map((opt) => `<${opt}>`).join(' ')}`
        : ''
      return `- \`/${cmd.name}${options}\`: ${cmd.description}`
    })
    .join('\n')

  return new EmbedBuilder()
    .setColor(TETO_COLOR_SV)
    .setTitle('**TetoBot Help**')
    .setDescription(
      'Kasane Teto Bot roleplays as Kasane Teto, responding to @mentions in whitelisted channels with AI-generated replies. 🎵'
    )
    .addFields(
      {
        name: '**Chat with Teto:**',
        value:
          '**@mention me in any channel!**\n' +
          "• In whitelisted channels: I'll respond immediately\n" +
          '• In new channels: Users with "Manage Channels" permission can @mention me to auto-whitelist the channel\n' +
          '• Example: `@Kasane Teto Hello! How are you today?`',
        inline: false,
      },
      {
        name: '**Channel Management:**',
        value:
          '• **Auto-whitelist**: @mention me with "Manage Channels" permission\n' +
          '• **Remove access**: Use `/blacklist` command\n' +
          '• Both require "Manage Channels" permission',
        inline: false,
      },
      {
        name: '**Commands:**',
        value: commandList,
        inline: false,
      },
      {
        name: '**Support:**',
        value:
          'For issues or feedback, please create an issue in our [GitHub Repo](https://github.com/jilv220/teto_bot/issues)',
        inline: false,
      }
    )
    .setTimestamp()
}
