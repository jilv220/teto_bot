import { DynamicStructuredTool } from '@langchain/core/tools'
import { Effect } from 'effect'
import { z } from 'zod'

// Schema for the get_lyrics tool input
const GetLyricsSchema = z.object({
  song_title: z.string().describe('The title of the song'),
  artist: z.string().describe('The name of the artist or band'),
})

// Tool implementation for getting song lyrics
export const getLyricsTool = new DynamicStructuredTool({
  name: 'get_lyrics',
  description:
    'Get the lyrics for a specific song by providing the song title and artist name',
  schema: GetLyricsSchema,
  func: async ({ song_title, artist }) => {
    console.log(`[get_lyrics] Called with: ${song_title} by ${artist}`)

    return Effect.gen(function* () {
      // Define response type
      interface LyricsResult {
        lyrics: string
        title: string
        artist: string
        source: string
      }

      let response: LyricsResult

      // First try to get lyrics from our internal API (cache)
      const cachedResult = yield* Effect.tryPromise({
        try: async () => {
          const { lyricsApi } = await import('../api')
          return await lyricsApi.getLyrics(artist, song_title)
        },
        catch: () => new Error('Cache miss'),
      }).pipe(Effect.catchAll(() => Effect.succeed(null)))

      if (cachedResult) {
        response = {
          lyrics: cachedResult.data.lyrics.lyrics,
          title: cachedResult.data.lyrics.title,
          artist: cachedResult.data.lyrics.artist,
          source: 'cache',
        }
        console.log('[get_lyrics] Found lyrics in cache for: ' + response.title)
        return (
          'Found lyrics for "' +
          response.title +
          '" by ' +
          response.artist +
          ':\n\n' +
          response.lyrics
        )
      }

      // If not found in cache, return message that lyrics service is not available
      const unavailableMessage =
        'Lyrics for "' +
        song_title +
        '" by ' +
        artist +
        ' are not available in our database. External lyrics services are currently disabled.'
      console.log('[get_lyrics] No lyrics found, returning unavailable message')
      return unavailableMessage
    }).pipe(
      Effect.catchAll((error: unknown) =>
        Effect.succeed(
          `Could not find lyrics for "${song_title}" by ${artist}. Error: ${
            error instanceof Error ? error.message : 'Unknown error occurred'
          }`
        )
      ),
      Effect.runPromise
    )
  },
})

// Export the tool for use in the LLM workflow
export const tools = [getLyricsTool]
