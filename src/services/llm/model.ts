import { ChatOpenAI } from '@langchain/openai'
import { Context, Effect, Layer } from 'effect'
import { appConfig } from '../config'
import { tools } from './tools'

export class LLMConversationModelContext extends Context.Tag(
  'LLMConversationModelContext'
)<LLMConversationModelContext, ReturnType<ChatOpenAI['bindTools']>>() {}

export class LLMSummarizationModelContext extends Context.Tag(
  'LLMSummarizationModelContext'
)<LLMSummarizationModelContext, ChatOpenAI>() {}

export class LLMVisionModelContext extends Context.Tag('LLMVisionModelContext')<
  LLMVisionModelContext,
  ReturnType<ChatOpenAI['bindTools']>
>() {}

export const LLMConversationModelLive = Layer.effect(
  LLMConversationModelContext,
  Effect.gen(function* () {
    const config = yield* appConfig
    const llmModel = new ChatOpenAI({
      apiKey: config.openrouterApiKey,
      model: config.conversationModel,
      temperature: 1.1,
      topP: 1,
      maxCompletionTokens: 225,
      configuration: {
        baseURL: config.openrouterBaseUrl,
      },
    })

    return llmModel.bindTools(tools)
  })
)

export const LLMSummarizationModelLive = Layer.effect(
  LLMSummarizationModelContext,
  Effect.gen(function* () {
    const config = yield* appConfig
    const llmModel = new ChatOpenAI({
      apiKey: config.openrouterApiKey,
      model: config.summarizationModel,
      temperature: 0.15,
      maxCompletionTokens: 300,
      configuration: {
        baseURL: config.openrouterBaseUrl,
      },
    })

    return llmModel
  })
)

export const LLMVisionModelLive = Layer.effect(
  LLMVisionModelContext,
  Effect.gen(function* () {
    const config = yield* appConfig
    const llmModel = new ChatOpenAI({
      apiKey: config.openrouterApiKey,
      model: config.visionModel,
      temperature: 0.8,
      topP: 1,
      maxCompletionTokens: 225,
      configuration: {
        baseURL: config.openrouterBaseUrl,
      },
    })

    return llmModel
  })
)
