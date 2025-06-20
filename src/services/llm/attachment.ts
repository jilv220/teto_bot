import type { Attachment } from 'discord.js'
import { Effect } from 'effect'

// Image formats supported by most vision models
const SUPPORTED_IMAGE_FORMATS = [
  'image/jpeg',
  'image/jpg',
  'image/png',
  'image/gif',
  'image/webp',
]

export const isImageAttachment = (attachment: Attachment): boolean => {
  return SUPPORTED_IMAGE_FORMATS.includes(attachment.contentType || '')
}

export const attachmentToBase64 = (attachment: Attachment) =>
  Effect.gen(function* () {
    if (!isImageAttachment(attachment)) {
      return yield* Effect.fail(
        new Error(`Unsupported image format: ${attachment.contentType}`)
      )
    }

    const response = yield* Effect.promise(() => fetch(attachment.url))

    if (!response.ok) {
      return yield* Effect.fail(
        new Error(`Failed to fetch image: ${response.statusText}`)
      )
    }

    const arrayBuffer = yield* Effect.promise(() => response.arrayBuffer())
    const base64 = Buffer.from(arrayBuffer).toString('base64')

    return {
      type: 'image_url' as const,
      image_url: {
        url: `data:${attachment.contentType};base64,${base64}`,
      },
    }
  })

export const processImageAttachments = (attachments: readonly Attachment[]) =>
  Effect.gen(function* () {
    const imageAttachments = attachments.filter(isImageAttachment)
    if (imageAttachments.length === 0) return []

    const imageProcessingEffects = imageAttachments.map(attachmentToBase64)

    return yield* Effect.all(imageProcessingEffects, {
      concurrency: 'unbounded',
    }).pipe(Effect.catchAll(() => Effect.succeed([])))
  })
