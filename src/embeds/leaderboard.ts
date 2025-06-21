import { EmbedBuilder, type GuildMember, type User } from 'discord.js'
import { TETO_COLOR_SV } from '.'
import type { LeaderboardEntry } from '../services'

/**
 * Build leaderboard title
 */
function buildLeaderboardTitle(): string {
  return "Teto's Intimacy Leaderboard (Top 10)\n"
}

/**
 * Get display name for a user, prioritizing nickname -> global name -> username
 */
function getDisplayName(
  userId: string,
  membersMap: Map<string, GuildMember>,
  usersMap: Map<string, User>
): string {
  // Try nickname from guild member first
  const member = membersMap.get(userId)
  if (member?.nickname) {
    return member.nickname
  }

  // Fall back to user global name or username
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
  membersMap: Map<string, GuildMember>,
  usersMap: Map<string, User>,
  guildName?: string
): EmbedBuilder {
  const leaderboardEntries = entries
    .map((entry, index) => {
      const rank = index + 1
      const displayName = getDisplayName(entry.userId, membersMap, usersMap)

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
