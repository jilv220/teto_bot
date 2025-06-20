/**
 * Discord related services
 */

import { Data } from 'effect'

export class DiscordMessageErorr extends Data.TaggedError(
  'DiscordMessageError'
)<{
  message: unknown
}> {}
