import { Layer } from 'effect'
import { ChannelRateLimiterLive } from './channelRateLimiter'
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
  ChannelRateLimiterLive
)
