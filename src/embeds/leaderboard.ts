import { EmbedBuilder, type User } from 'discord.js'
import { TETO_COLOR_SV } from '.'
import type { LeaderboardEntry } from '../services'

/**
 * Build leaderboard title
 */
function buildLeaderboardTitle(): string {
  return "Teto's Intimacy Leaderboard (Top 10)\n"
}

/**
 * Get display name for a user, using global name or username
 * Refactored to work without guild member data (no nicknames available)
 */
function getDisplayName(userId: string, usersMap: Map<string, User>): string {
  const user = usersMap.get(userId)
  if (user) {
    return user.globalName || user.username || `User#${userId}`
  }

  return `User#${userId}`
}

/**
 * Build formatted leaderboard embed
 */
export function buildLeaderboardEmbed(
  entries: LeaderboardEntry[],
  usersMap: Map<string, User>,
  guildName?: string
): EmbedBuilder {
  const leaderboardEntries = entries
    .map((entry, index) => {
      const rank = index + 1
      const displayName = getDisplayName(entry.userId, usersMap)

      // Add emoji for top 3 positions
      let rankEmoji = ''
      if (rank === 1) rankEmoji = '🥇 '
      else if (rank === 2) rankEmoji = '🥈 '
      else if (rank === 3) rankEmoji = '🥉 '
      else rankEmoji = `${rank}. `

      return `${rankEmoji} ${displayName} - **${entry.intimacy}**`
    })
    .join('\n')

  const embed = new EmbedBuilder()
    .setTitle(buildLeaderboardTitle())
    .setDescription(leaderboardEntries)
    .setColor(TETO_COLOR_SV) // Hot pink color for Teto
    .setTimestamp()
    .setFooter({
      text: guildName
        ? `${guildName} • Intimacy Leaderboard`
        : 'Intimacy Leaderboard',
    })

  return embed
}
