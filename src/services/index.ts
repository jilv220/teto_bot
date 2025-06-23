import { Layer } from 'effect'
import { ApiServiceLive } from './api'
import { ChannelRateLimiterLive } from './channelRateLimiter'
import { ChannelServiceLive } from './channelService'
import { ClientLive } from './client'
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
  ChannelServiceLive
)

// Re-export service components
export * from './api'
export * from './channelService'
