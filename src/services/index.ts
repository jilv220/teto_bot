import { Layer } from 'effect'
import { ApiServiceLive } from './api'
import { ChannelServiceLive } from './channel'
import { ChannelRateLimiterLive } from './channelRateLimiter'
import { ClientLive } from './client'
import { DiscordServiceLive } from './discord'
import {
  LLMConversationModelLive,
  LLMLive,
  LLMSummarizationModelLive,
  LLMVisionModelLive,
} from './llm'

/**
 *  Exporting Layers in index.ts of Services
 */

export const LLMLayer = LLMLive.pipe(
  Layer.provide(LLMSummarizationModelLive),
  Layer.provide(LLMConversationModelLive),
  Layer.provide(LLMVisionModelLive)
)

export const MainLive = Layer.mergeAll(
  ClientLive,
  LLMLayer,
  LLMConversationModelLive,
  ChannelRateLimiterLive,
  ApiServiceLive,
  ChannelServiceLive,
  DiscordServiceLive
)

// Re-export service components
export * from './api'
export * from './channel'
