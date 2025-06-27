import type { Message } from 'discord.js'
import { Context, Data, Effect, Layer } from 'effect'

/**
 * Channel Service - handles channel-related operations
 */
export class MessagesService extends Context.Tag('MessagesService')<
  MessagesService,
  {
    removeBotMention: (message: Message) => Effect.Effect<string, never>
  }
>() {}

const make = Effect.gen(function* () {
  return MessagesService.of({
    removeBotMention: (message: Message) => {
      const botMention = `<@${message.client.user.id}>`
      const botNicknameMention = `<@!${message.client.user.id}>`
      const content = message.content
        .replace(botMention, '')
        .replace(botNicknameMention, '')
        .trim()
      return Effect.succeed(content)
    },
  })
})

/**
 * Messages Service Implementation
 */
export const MessagesServiceLive = Layer.effect(MessagesService, make)

export * from './filter'
