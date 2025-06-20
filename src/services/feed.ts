/**
 * Service for handling feed cooldowns and feed-related business logic
 */

import { formatTimeLeft } from '../utils/format'

/**
 * Check if user can feed Teto (daily cooldown based on UTC midnight)
 */
export function checkFeedCooldown(lastFeed?: string): {
  allowed: boolean
  timeLeft?: number
} {
  if (!lastFeed) {
    return { allowed: true }
  }

  const now = new Date()
  const lastFeedDate = new Date(lastFeed)

  // Get today's UTC date (midnight)
  const todayUTC = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
  )

  // Get the last feed UTC date (midnight)
  const lastFeedDateUTC = new Date(
    Date.UTC(
      lastFeedDate.getUTCFullYear(),
      lastFeedDate.getUTCMonth(),
      lastFeedDate.getUTCDate()
    )
  )

  // If the last feed was before today (UTC), allow feeding
  if (lastFeedDateUTC < todayUTC) {
    return { allowed: true }
  }

  // If fed today, calculate time until next UTC midnight
  const tomorrowStartUTC = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)
  )

  const timeLeft = tomorrowStartUTC.getTime() - now.getTime()
  return { allowed: false, timeLeft }
}

/**
 * Get formatted feed cooldown status message
 */
export function getFeedCooldownMessage(lastFeed?: string): string {
  const cooldownCheck = checkFeedCooldown(lastFeed)

  if (cooldownCheck.allowed) {
    return '**Feed Status:** You can feed Teto now'
  }
  if (cooldownCheck.timeLeft) {
    return `**Feed Status:** Next feed available in ${formatTimeLeft(cooldownCheck.timeLeft)}`
  }
  return '**Feed Status:** On cooldown'
}

/**
 * Build cooldown message for feed command responses
 */
export function buildFeedCooldownMessage(timeLeft?: number): string {
  if (timeLeft) {
    return `You've already fed Teto today! Try again in ${formatTimeLeft(timeLeft)}.`
  }
  return "You've already fed Teto today!"
}

/**
 * Build success message for feeding
 */
export function buildFeedSuccessMessage(intimacy?: number): string {
  if (intimacy !== undefined) {
    return `You fed Teto! Your intimacy with her increased by 5.\nCurrent intimacy: ${intimacy}. 💖`
  }
  return 'You fed Teto! Your intimacy with her increased by 5.'
}
