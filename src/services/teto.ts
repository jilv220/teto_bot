/**
 * Service for handling Teto relationship tiers and related business logic
 */

export interface RelationshipTier {
  name: string
  requiredIntimacy: number
}

export const RELATIONSHIP_TIERS: RelationshipTier[] = [
  { name: 'Husband', requiredIntimacy: 1000 },
  { name: 'Best Friend', requiredIntimacy: 500 },
  { name: 'Close Friend', requiredIntimacy: 200 },
  { name: 'Good Friend', requiredIntimacy: 101 },
  { name: 'Friend', requiredIntimacy: 51 },
  { name: 'Buddy', requiredIntimacy: 21 },
  { name: 'Acquaintance', requiredIntimacy: 11 },
  { name: 'Familiar Face', requiredIntimacy: 5 },
  { name: 'Stranger', requiredIntimacy: 0 },
]

/**
 * Get current and next tier information based on intimacy level
 */
export function getTierInfo(intimacy: number): {
  current: { value: number; tier: string }
  next: { value: number; tier: string }
} {
  // Since tiers are in descending order (highest first), find the first tier the user qualifies for
  let currentTier = RELATIONSHIP_TIERS[RELATIONSHIP_TIERS.length - 1] // Default to lowest tier (Stranger)
  let nextTier = RELATIONSHIP_TIERS[RELATIONSHIP_TIERS.length - 2] // Default to second lowest

  // Find the current tier (first tier where intimacy >= required)
  for (let i = 0; i < RELATIONSHIP_TIERS.length; i++) {
    if (intimacy >= RELATIONSHIP_TIERS[i].requiredIntimacy) {
      currentTier = RELATIONSHIP_TIERS[i]
      // Next tier is the previous one in the array (higher intimacy requirement)
      nextTier = RELATIONSHIP_TIERS[i - 1] || RELATIONSHIP_TIERS[i] // If at max tier, next = current
      break
    }
  }

  return {
    current: {
      value: currentTier.requiredIntimacy,
      tier: currentTier.name,
    },
    next: {
      value: nextTier.requiredIntimacy,
      tier: nextTier.name,
    },
  }
}

/**
 * Calculate intimacy gain from feeding (business rule)
 */
export const FEED_INTIMACY_GAIN = 5

/**
 * Build the message showing progress toward the next relationship tier
 */
export function buildNextTierMessage(
  currentTier: string,
  nextTier: string,
  currentValue: number,
  nextValue: number
): string {
  if (currentTier === nextTier) {
    return `**Status:** Highest Tier (${currentTier}) Reached`
  }
  const diff = nextValue - currentValue
  return `**Next Tier:** __${diff}__ more intimacy to reach ${nextTier}`
}
