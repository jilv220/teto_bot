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
      } else {
        // If not found in cache, return message that lyrics service is not available
        response = {
          lyrics: `Lyrics for "${song_title}" by ${artist} are not available in our database. External lyrics services are currently disabled.`,
          title: song_title,
          artist: artist,
          source: 'unavailable',
        }
      }

      return JSON.stringify({
        success: true,
        data: response,
        message: `Found lyrics for "${song_title}" by ${artist}`,
      })
    }).pipe(
      Effect.catchAll((error: unknown) =>
        Effect.succeed(
          JSON.stringify({
            success: false,
            error:
              error instanceof Error ? error.message : 'Unknown error occurred',
            message: `Could not find lyrics for "${song_title}" by ${artist}`,
          })
        )
      ),
      Effect.runPromise
    )
  },
})

// Export the tool for use in the LLM workflow
export const tools = [getLyricsTool]
