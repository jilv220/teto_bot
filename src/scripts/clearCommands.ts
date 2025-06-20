import { Effect } from 'effect'
import { pushCommands } from './pushCommands'

/**
 * Script to clear commands for dev guild/server
 */

const program = pushCommands([])

Effect.runPromise(program)
