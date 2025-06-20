/**
 * Service for handling voting system and credit-related business logic
 */

import { Effect } from 'effect'
import { appConfig } from './config'

// =====================
// VOTING & CREDITS CONSTANTS
// =====================

// TODO: Should provided by endpoint
export const VOTE_CREDIT_BONUS = 30

const { voteUrl } = Effect.runSync(appConfig)

/**
 * Check if user has voted within the last 12 hours
 */
export function hasVotedRecently(lastVotedAt?: string): boolean {
  if (!lastVotedAt) return false

  const lastVote = new Date(lastVotedAt)
  const now = new Date()
  const twelveHoursAgo = new Date(now.getTime() - 12 * 60 * 60 * 1000)

  return lastVote > twelveHoursAgo
}

/**
 * Build the voting status section for user status messages
 */
export function buildVotingStatusSection(hasVoted: boolean): string {
  if (hasVoted) {
    return `✅ **Voting Status**: Active (voted within 12 hours)
🎉 Thanks for voting! You can vote again after 12 hours to get **${VOTE_CREDIT_BONUS} more credits**!

`
  }
  return `❌ **Voting Status**: Not voted recently
💡 Vote for the bot on [top.gg](${voteUrl}) to get **${VOTE_CREDIT_BONUS} credits** immediately!

`
}

/**
 * Build the daily message status section
 */
export function buildMessageStatusSection(credits: number): string {
  return `💳 **Your Message Credits**

• Credits available: **${credits}**
• Each message costs 1 credit

`
}
