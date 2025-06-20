import {
  HumanMessage,
  RemoveMessage,
  SystemMessage,
} from '@langchain/core/messages'
import {
  Annotation,
  END,
  MemorySaver,
  MessagesAnnotation,
  START,
  StateGraph,
} from '@langchain/langgraph'
import { Context, Effect, Layer } from 'effect'
import { v4 as uuidv4 } from 'uuid'
import { appConfig } from '../config'
import {
  LLMConversationModelContext,
  LLMSummarizationModelContext,
  LLMVisionModelContext,
} from './model'
import {
  buildSummaryExtensionMessage,
  buildSummaryMessage,
  systemPromptEffect,
} from './prompt'

export class LLMContext extends Context.Tag('LLMContext')<
  LLMContext,
  // Bruh...
  ReturnType<typeof StateGraph.prototype.compile>
>() {}

// Extend MessagesAnnotation to include summary and hasImages flag
const GraphAnnotation = Annotation.Root({
  ...MessagesAnnotation.spec,
  summary: Annotation<string>({
    reducer: (_, action) => action,
    default: () => '',
  }),
  hasImages: Annotation<boolean>({
    reducer: (_, action) => action,
    default: () => false,
  }),
  // Add user context (username and intimacy level)
  userContext: Annotation<{
    username: string
    intimacyLevel: number
  }>({
    reducer: (_, action) => action,
    default: () => ({
      username: '',
      intimacyLevel: 0,
    }),
  }),
})

export const LLMLive = Layer.effect(
  LLMContext,
  Effect.gen(function* () {
    const config = yield* appConfig

    const conversationModel = yield* LLMConversationModelContext
    const summarizationModel = yield* LLMSummarizationModelContext
    const visionModel = yield* LLMVisionModelContext

    // Shared conversation logic
    const createConversationNode =
      (model: typeof conversationModel) =>
      (state: typeof GraphAnnotation.State) =>
        Effect.gen(function* () {
          const { summary, userContext } = state
          let { messages } = state

          const systemPrompt = yield* systemPromptEffect

          // If a summary exists, add it as a system message
          if (summary) {
            const summaryMessage = new SystemMessage({
              id: uuidv4(),
              content: `Summary of conversation earlier: ${summary}`,
            })
            messages = [summaryMessage, ...messages]
          }

          // Use the system prompt template with the messages and user context
          const formattedPrompt = yield* Effect.promise(() =>
            systemPrompt.formatMessages({
              messages: messages,
              ...userContext, // Spread the user context variables
            })
          )

          const response = yield* Effect.promise(() =>
            model.invoke(formattedPrompt)
          )

          return { messages: [response] }
        }).pipe(Effect.runPromise)

    // Create specific nodes using the shared logic
    const conversationNode = createConversationNode(conversationModel)
    const visionNode = createConversationNode(visionModel)

    // Summarization node
    const summarizeConversation = async (
      state: typeof GraphAnnotation.State
    ) => {
      const { summary, messages } = state

      const summaryMessage = summary
        ? buildSummaryExtensionMessage(summary)
        : buildSummaryMessage()

      const allMessages = [
        ...messages,
        new HumanMessage({
          id: uuidv4(),
          content: summaryMessage,
        }),
      ]

      const response = await summarizationModel.invoke(allMessages)

      // Delete older messages, keep only the most recent ones
      const deleteMessages = messages
        .slice(0, -config.recentMessagesKeep)
        .filter((m) => m.id)
        .map((m) => new RemoveMessage({ id: m.id as string }))

      const content = response.content
      if (!content || typeof content !== 'string') {
        throw new Error(
          'Expected a string response from the summarization model'
        )
      }

      return {
        summary: content as string,
        messages: deleteMessages,
      }
    }

    // Determine which model to use based on hasImages flag
    const routeToModel = (
      state: typeof GraphAnnotation.State
    ): 'conversation' | 'vision' => {
      return state.hasImages ? 'vision' : 'conversation'
    }

    // Determine whether to continue or summarize
    const shouldContinue = (
      state: typeof GraphAnnotation.State
    ): 'summarize_conversation' | typeof END => {
      const messages = state.messages

      // If there are more than MAX_MESSAGES, summarize the conversation
      if (messages.length > config.summarizationThreshold) {
        return 'summarize_conversation'
      }

      // Otherwise we can just end
      return END
    }

    // Create the graph with vision support
    const workflow = new StateGraph(GraphAnnotation)
      .addNode('conversation', conversationNode)
      .addNode('vision', visionNode)
      .addNode('summarize_conversation', summarizeConversation)
      .addConditionalEdges(START, routeToModel)
      .addConditionalEdges('conversation', shouldContinue)
      .addConditionalEdges('vision', shouldContinue)
      .addEdge('summarize_conversation', END)

    // Add memory
    const memory = new MemorySaver()
    const llm = workflow.compile({ checkpointer: memory })

    return llm
  })
)

export * from './model'
