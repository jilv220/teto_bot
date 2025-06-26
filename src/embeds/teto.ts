import { EmbedBuilder } from 'discord.js'
import { Effect } from 'effect'
import { TETO_COLOR_SV } from '.'
import { appConfig } from '../services/config'
import { getFeedCooldownMessage } from '../services/feed'
import { buildNextTierMessage, getTierInfo } from '../services/teto'
import { VOTE_CREDIT_BONUS } from '../services/voting'

/**
 * Interface for combined user metrics
 */
export interface UserMetrics {
  intimacy: number
  dailyMessageCount: number
}

/**
 * Interface for user status including credits and voting
 */
export interface UserStatus {
  messageCredits: number
  hasVoted: boolean
}

/**
 * Interface for user guild data
 */
export interface UserGuildData {
  lastFeed?: string
}

/**
 * Interface for Discord user data
 */
export interface DiscordUserData {
  username: string
  avatarURL?: string | null
}

const config = Effect.runSync(appConfig)

/**
 * Build the Teto status embed
 */
export function buildTetoStatusEmbed(
  metrics: UserMetrics | null,
  status: UserStatus,
  userGuild: UserGuildData | null,
  userData: DiscordUserData,
  guildName?: string
): EmbedBuilder {
  const messageCreditsParts = [
    '### 💳 Message Credits',
    `**Credits Available:** ${status.messageCredits}`,
    '**Cost:** Each message costs 1 credit',
    'Daily credit refill happens at **midnight UTC (12am)** each day.',
  ]

  // Build comprehensive description
  const descriptionParts = metrics
    ? [
        '### 💕 Relationship Status',
        `**Intimacy:** ${metrics.intimacy}`,
        ...(() => {
          const { current, next } = getTierInfo(metrics.intimacy)
          const relationshipPart = `**Relationship:** ${current.tier}`
          const nextTierPart = buildNextTierMessage(
            current.tier,
            next.tier,
            current.value,
            next.value
          )

          return [relationshipPart, nextTierPart]
        })(),
        userGuild ? getFeedCooldownMessage(userGuild.lastFeed) : null,
        `**Daily Messages:** ${metrics.dailyMessageCount} in this guild`,
        ...messageCreditsParts,
        '',
      ]
    : [...messageCreditsParts, '']

  // Add voting reminder if not voted
  if (!status.hasVoted) {
    descriptionParts.push(
      `**Reminder:** You haven't voted in the last 12h! [Vote](${config.voteUrl}) for ${VOTE_CREDIT_BONUS} credits immediately!`
    )
  }

  const embed = new EmbedBuilder()
    .setAuthor({
      name: `${userData.username}`,
      iconURL: userData.avatarURL || undefined,
    })
    .setColor(TETO_COLOR_SV)
    .setTimestamp()
    .setFooter({
      text: guildName ? `${guildName} • Teto Status` : 'Teto Status',
    })
    .setDescription(descriptionParts.join('\n'))

  return embed
}
