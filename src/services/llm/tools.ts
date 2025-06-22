import { DynamicStructuredTool } from '@langchain/core/tools'
import { Effect } from 'effect'
import { z } from 'zod'

// Schema for the get_lyrics tool input
const GetLyricsSchema = z.object({
  song_title: z.string().describe('The title of the song'),
  artist: z.string().describe('The name of the artist or band'),
})

// Schema for the search_lyrics tool input
const SearchLyricsSchema = z.object({
  song_title: z.string().describe('The title of the song to search for'),
})

// Tool implementation for getting song lyrics
export const getLyricsTool = new DynamicStructuredTool({
  name: 'get_lyrics',
  description:
    'Get the lyrics for a specific song when you know both the song title and artist name. Use this when the user provides both the song title and artist.',
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

export const searchLyricsTool = new DynamicStructuredTool({
  name: 'search_lyrics',
  description:
    "Search for song lyrics when you only know the song title but not the artist. Use this when the user asks for lyrics but doesn't specify the artist name.",
  schema: SearchLyricsSchema,
  func: async ({ song_title }) => {
    console.log(`[search_lyrics] Called with: ${song_title}`)

    return Effect.gen(function* () {
      // Try to search for the song in our internal API (cache)
      const searchResult = yield* Effect.tryPromise({
        try: async () => {
          const { lyricsApi } = await import('../api')
          // Use the existing getLyricsByTitle method which returns multiple matches
          return await lyricsApi.getLyricsByTitle(song_title)
        },
        catch: () => new Error('Search failed'),
      }).pipe(Effect.catchAll(() => Effect.succeed(null)))

      if (searchResult?.data?.lyrics && searchResult.data.lyrics.length > 0) {
        // Return the first match (or you could return multiple options)
        const lyrics = searchResult.data.lyrics[0]
        console.log('[search_lyrics] Found lyrics for: ' + lyrics.title)
        return (
          'Found lyrics for "' +
          lyrics.title +
          '" by ' +
          lyrics.artist +
          ':\n\n' +
          lyrics.lyrics
        )
      }

      // If not found in cache, return message that lyrics service is not available
      const unavailableMessage =
        'Could not find lyrics for "' +
        song_title +
        '" in our database. External lyrics services are currently disabled. Try providing both the song title and artist name for better results.'
      console.log(
        '[search_lyrics] No lyrics found, returning unavailable message'
      )
      return unavailableMessage
    }).pipe(
      Effect.catchAll((error: unknown) =>
        Effect.succeed(
          `Could not search for lyrics for "${song_title}". Error: ${
            error instanceof Error ? error.message : 'Unknown error occurred'
          }`
        )
      ),
      Effect.runPromise
    )
  },
})

// Export the tools for use in the LLM workflow
export const tools = [getLyricsTool, searchLyricsTool]
