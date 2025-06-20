/**
 * Pure formatting utilities
 */

/**
 * Format time left in a human-readable format
 */
export function formatTimeLeft(milliseconds: number): string {
  const hours = Math.floor(milliseconds / (1000 * 60 * 60))
  const minutes = Math.floor((milliseconds % (1000 * 60 * 60)) / (1000 * 60))

  if (hours > 0) {
    return `${hours} hour${hours > 1 ? 's' : ''} and ${minutes} minute${minutes !== 1 ? 's' : ''}`
  }
  return `${minutes} minute${minutes !== 1 ? 's' : ''}`
}

export const formatNum = (num: number): string => {
  return new Intl.NumberFormat().format(num)
}
