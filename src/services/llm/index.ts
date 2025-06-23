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
  REMOVE_ALL_MESSAGES,
  START,
  StateGraph,
} from '@langchain/langgraph'
import { ToolNode } from '@langchain/langgraph/prebuilt'
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
import { tools } from './tools'

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
    intimacy: number
  }>({
    reducer: (_, action) => action,
    default: () => ({
      username: '',
      intimacy: 0,
    }),
  }),
  // Add timestamp for detecting conversation gaps
  lastMessageTimestamp: Annotation<number>({
    reducer: (_, action) => action,
    default: () => Date.now(),
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
    const createConversation =
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
    const conversation = createConversation(conversationModel)
    const vision = createConversation(visionModel)

    // Create tool node for executing tools
    const toolNode = new ToolNode(tools)

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

    // Delete old messages but preserve current user message
    const deleteMessages = (state: typeof GraphAnnotation.State) => {
      // Keep only the most recent message (which should be the current user message)
      const currentMessage = state.messages[state.messages.length - 1]

      // Create remove messages for all but the current one
      const messagesToDelete = state.messages
        .slice(0, -1) // All except the last one
        .filter((m) => m.id)
        .map((m) => new RemoveMessage({ id: m.id as string }))

      return {
        messages: messagesToDelete,
        summary: '', // Clear summary too when starting fresh
        lastMessageTimestamp: Date.now(), // Update timestamp
      }
    }

    // Check if there's a large gap indicating a new topic
    const checkConversationGap = (
      state: typeof GraphAnnotation.State
    ): 'delete_messages' | 'router' => {
      const currentTime = Date.now()
      const { lastMessageTimestamp } = state

      // If gap is larger than configured threshold (e.g., 30 minutes), treat as new topic
      const gapThresholdMs = config.conversationGapThreshold
      const gap = currentTime - lastMessageTimestamp

      if (gap > gapThresholdMs) {
        return 'delete_messages'
      }
      return 'router'
    }

    // Don't do anything, just pass through
    const passThrough = (state: typeof GraphAnnotation.State) => state

    // Determine which model to use based on hasImages flag
    const routeToModel = (
      state: typeof GraphAnnotation.State
    ): 'conversation' | 'vision' => {
      return state.hasImages ? 'vision' : 'conversation'
    }

    // Unified routing function for conversation/vision nodes
    const routeFromModel = (
      state: typeof GraphAnnotation.State
    ): 'tools' | 'summarize_conversation' | typeof END => {
      const messages = state.messages
      const lastMessage = messages[messages.length - 1]

      // Check if the last message has tool calls - if so, execute tools
      if (
        lastMessage &&
        'tool_calls' in lastMessage &&
        Array.isArray(lastMessage.tool_calls) &&
        lastMessage.tool_calls.length > 0
      ) {
        return 'tools'
      }

      // If there are more than summarizationThreshold messages, summarize the conversation
      if (messages.length > config.summarizationThreshold) {
        return 'summarize_conversation'
      }

      // Otherwise we can just end
      return END
    }

    // Determine which model to route back to after tool execution
    const routeAfterTools = (
      state: typeof GraphAnnotation.State
    ): 'conversation' | 'vision' => {
      return state.hasImages ? 'vision' : 'conversation'
    }

    // Create the graph with vision support and tool execution
    const workflow = new StateGraph(GraphAnnotation)
      .addNode('conversation', conversation)
      .addNode('vision', vision)
      .addNode('tools', toolNode)
      .addNode('summarize_conversation', summarizeConversation)
      .addNode('delete_messages', deleteMessages)
      .addNode('router', passThrough)
      .addConditionalEdges(START, checkConversationGap)
      .addConditionalEdges('router', routeToModel)
      .addConditionalEdges('conversation', routeFromModel)
      .addConditionalEdges('vision', routeFromModel)
      .addConditionalEdges('tools', routeAfterTools)
      .addEdge('summarize_conversation', END)
      .addEdge('delete_messages', 'router')

    // Add memory
    const memory = new MemorySaver()
    const llm = workflow.compile({ checkpointer: memory })

    return llm
  })
)

export * from './model'
