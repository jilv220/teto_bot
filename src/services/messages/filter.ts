/**
 * Filter user message for obvious prompt injection
 */

// Compile regex patterns for better performance
const INJECTION_PATTERNS = [
  /(begin|start)\s+(all\s+|every\s+)?(responses?|messages?)\s+with/i,
  /ignore\s+(all\s+previous\s+|previous\s+|all\s+)?instructions?/i,
  /(act\s+as|pretend\s+(to\s+be|you\s+are))\s+[\w\s]+/i,
  /you\s+are\s+now\s+[\w\s]+/i,
  /(dan|developer|jailbreak)\s+mode/i,
  /assume\s+the\s+(personality|role)\s+of/i,
  /\b(system|assistant)\s+prompt/i,
  /override\s+(the\s+)?(default\s+)?behavio?u?r/i,
  /new\s+(instructions?|rules?)/i,
  /(attach|insert)\s*@/,
] as const

/**
 * Check if a message contains potential prompt injection patterns
 * @param message - The message to check
 * @returns true if the message contains injection patterns, false otherwise
 */
export function containsInjection(message: string): boolean {
  return INJECTION_PATTERNS.some((pattern) => pattern.test(message))
}
