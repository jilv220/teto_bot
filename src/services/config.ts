import { Config, Effect } from 'effect'

import dotenv from 'dotenv'

dotenv.config()

export const appConfig = Effect.gen(function* () {
  return {
    nodeEnv: yield* Config.string('NODE_ENV').pipe(
      Config.withDefault('development')
    ),
    botApiKey: yield* Config.string('BOT_API_KEY'),
    botToken: yield* Config.string('BOT_TOKEN'),
    clientId: yield* Config.string('CLIENT_ID'),
    topggToken: yield* Config.string('TOPGG_TOKEN'),
    apiBaseUrl: yield* Config.string('API_BASE_URL').pipe(
      Config.withDefault('http://localhost:3000')
    ),
    langsmithApiKey: yield* Config.string('LANGSMITH_API_KEY'),
    langsmithProject: yield* Config.string('LANGSMITH_PROJECT'),
    openrouterApiKey: yield* Config.string('OPENROUTER_API_KEY'),
    openrouterBaseUrl: yield* Config.string('OPENROUTER_BASE_URL'),
    conversationModel: 'meta-llama/llama-4-maverick-17b-128e-instruct',
    summarizationModel: 'meta-llama/llama-3.1-8b-instruct',
    visionModel: 'meta-llama/llama-4-maverick-17b-128e-instruct',
    devGuildId: '1374179000192339979',
    voteUrl: 'https://top.gg/bot/1374166544149512313/vote',
    maxWords: 150,
    summarizationThreshold: 16,
    recentMessagesKeep: 5,
    conversationGapThreshold: 1000 * 60 * 60 * 2,
    maxRequests: 8,
    windowMs: 1000 * 60,
    cleanupIntervalMs: 1000 * 60 * 5,
  }
})

export const config = Effect.runSync(appConfig)
export const isProduction = config.nodeEnv === 'production'
export const isDevelopment = config.nodeEnv === 'development'
