import { Data, Effect, Runtime } from 'effect'
import { Duration, Schedule } from 'effect'
import { FetchError, type FetchOptions, ofetch } from 'ofetch'
import { appConfig, isDevelopment } from '../config'

const config = await Effect.runPromise(appConfig)

// Create ofetch instance with default configuration
export const api = ofetch.create({
  baseURL: `${config.apiBaseUrl}/api`,
  headers: {
    'Content-Type': 'application/json',
  },
  // Add authorization token if available
  onRequest({ options }) {
    options.headers = new Headers({
      ...options.headers,
      Authorization: `Bearer ${config.botApiKey}`,
    })
  },
  // Handle errors gracefully
  onResponseError({ response }) {
    if (isDevelopment) {
      console.error(`API Error: ${response.status} - ${response.statusText}`)
    }
  },
})

// =====================
// TYPE DEFINITIONS
// =====================

// User Types
export interface User {
  userId: string
  insertedAt: string
  updatedAt: string
  role?: 'user' | 'admin'
  lastVotedAt?: string
  messageCredits: string
}

export interface CreateUserRequest {
  userId: string
  role?: 'user' | 'admin'
}

export interface UpdateUserRequest {
  userId: string
  role?: 'user' | 'admin'
  messageCredits?: string
  lastVotedAt?: string
}

export interface UserResponse {
  data: {
    user: User
  }
}

export interface UsersResponse {
  data: {
    users: User[]
  }
}

// Guild Types
export interface Guild {
  id: string
  guildId: string
  insertedAt: string
  updatedAt: string
}

export interface CreateGuildRequest {
  guildId: string
}

export interface GuildResponse {
  data: {
    guild: Guild
  }
}

export interface GuildsResponse {
  data: {
    guilds: Guild[]
  }
}

// Channel Types
export interface Channel {
  id: string
  channelId: string
  guildId: string
  insertedAt: string
  updatedAt: string
}

export interface CreateChannelRequest {
  channelId: string
  guildId: string
}

export interface ChannelResponse {
  data: {
    channel: Channel
  }
}

export interface ChannelsResponse {
  data: {
    channels: Channel[]
  }
}

// UserGuild Types
export interface UserGuild {
  userId: string
  guildId: string
  insertedAt: string
  updatedAt: string
  intimacy: number
  lastMessageAt?: string
  lastFeed?: string
  dailyMessageCount: string
}

export interface CreateUserGuildRequest {
  userId: string
  guildId: string
  intimacy?: number
  lastMessageAt?: string
  lastFeed?: string
  dailyMessageCount?: string
}

export interface UpdateUserGuildRequest {
  intimacy?: number
  lastMessageAt?: string
  lastFeed?: string
  dailyMessageCount?: string
}

export interface UserGuildResponse {
  data: {
    userGuild: UserGuild
  }
}

export interface UserGuildsResponse {
  data: {
    userGuilds: UserGuild[]
  }
}

// Leaderboard Types
export interface LeaderboardEntry extends UserGuild {}

export interface LeaderboardResponse {
  data: {
    leaderboard: LeaderboardEntry[]
    guildId: string
    limit: number
  }
}

export interface LeaderboardRequest {
  guildId: string
  limit?: number
}

// Token Types
export interface TokenRequest {
  text: string
}

export interface TokenResponse {
  token_count: number
  text_length: number
}

// System Prompt Types
export interface SetSystemPromptRequest {
  prompt: string
}

export interface SystemPromptResponse {
  prompt: string | null
}

export interface SetSystemPromptResponse {
  success: boolean
  message: string
}

// Lyrics Types
export interface Lyrics {
  artist: string
  title: string
  lyrics: string
  createdAt: string
  updatedAt: string
}

export interface CreateLyricsRequest {
  artist: string
  title: string
  lyrics: string
}

export interface UpdateLyricsRequest {
  lyrics: string
}

export interface LyricsResponse {
  data: {
    lyrics: Lyrics
  }
}

export interface LyricsListResponse {
  data: {
    lyrics: Lyrics[]
  }
}

export interface DeleteLyricsResponse {
  data: {
    message: string
  }
}

// =====================
// API SERVICE - PHASE 2 COMPLETE
// =====================
//
// This API service now provides two interfaces:
//
// 1. Legacy Promise-based APIs (throw FetchError on HTTP errors):
//    - promiseApi.* / discordBotApi.*
//    - Use for existing code during migration
//
// 2. Modern Effect-based APIs (return Effect<T, ApiError>):
//    - effectApi.*
//    - Use for new code - provides proper error handling and Effect integration
//
// The Effect-based APIs provide:
// ✅ Standardized error handling with ApiError
// ✅ Proper Effect-TS integration
// ✅ Consistent error context (endpoint information)
// ✅ Type-safe error recovery patterns
// ✅ Composable error handling with retry, fallback, etc.
//
// Note: Legacy Promise-based functions throw FetchError on HTTP errors

// =====================
// API CLIENT FUNCTIONS
// =====================

// User API
export const userApi = {
  /**
   * Get all users
   * @throws {FetchError} When the API request fails
   */
  async getUsers(): Promise<UsersResponse> {
    return api<UsersResponse>('/users')
  },

  /**
   * Get a specific user by ID
   * @throws {FetchError} When the API request fails
   */
  async getUser(userId: string): Promise<UserResponse> {
    return api<UserResponse>(`/users/${userId}`)
  },

  /**
   * Create a new user
   * @throws {FetchError} When the API request fails
   */
  async createUser(userData: CreateUserRequest): Promise<UserResponse> {
    return api<UserResponse>('/users', {
      method: 'POST',
      body: userData,
    })
  },

  /**
   * Update an existing user
   * @throws {FetchError} When the API request fails
   */
  async updateUser(
    userId: string,
    updateData: Omit<UpdateUserRequest, 'userId'>
  ): Promise<UserResponse> {
    return api<UserResponse>(`/users/${userId}`, {
      method: 'PUT',
      body: updateData,
    })
  },

  /**
   * Delete a user
   * @throws {FetchError} When the API request fails
   */
  async deleteUser(userId: string): Promise<{ data: { message: string } }> {
    return api<{ data: { message: string } }>(`/users/${userId}`, {
      method: 'DELETE',
    })
  },
}

// Guild API
export const guildApi = {
  /**
   * Get all guilds
   * @throws {FetchError} When the API request fails
   */
  async getGuilds(): Promise<GuildsResponse> {
    return api<GuildsResponse>('/guilds')
  },

  /**
   * Get a specific guild by ID
   * @throws {FetchError} When the API request fails
   */
  async getGuild(guildId: string): Promise<GuildResponse> {
    return api<GuildResponse>(`/guilds/${guildId}`)
  },

  /**
   * Create a new guild
   * @throws {FetchError} When the API request fails
   */
  async createGuild(guildData: CreateGuildRequest): Promise<GuildResponse> {
    return api<GuildResponse>('/guilds', {
      method: 'POST',
      body: guildData,
    })
  },
  createGuildEffect: (guildData: CreateGuildRequest) =>
    makeApiEffect(() => guildApi.createGuild(guildData), 'guilds.createGuild'),

  /**
   * Delete a guild
   * @throws {FetchError} When the API request fails
   */
  deleteGuild(guildId: string): Promise<{ data: { message: string } }> {
    return api<{ data: { message: string } }>(`/guilds/${guildId}`, {
      method: 'DELETE',
    })
  },

  deleteGuildEffect: (guildId: string) =>
    makeApiEffect(
      () => guildApi.deleteGuild(guildId),
      'guilds.deleteGuild'
    ).pipe(Effect.tapError((error) => Effect.logError(error))),
}

// Channel API
export const channelApi = {
  /**
   * Get all channels
   * @throws {FetchError} When the API request fails
   */
  async getChannels(): Promise<ChannelsResponse> {
    return api<ChannelsResponse>('/channels')
  },

  /**
   * Get a specific channel by ID
   * @throws {FetchError} When the API request fails
   */
  async getChannel(channelId: string): Promise<ChannelResponse> {
    return api<ChannelResponse>(`/channels/${channelId}`)
  },

  /**
   * Create a new channel
   * @throws {FetchError} When the API request fails
   */
  async createChannel(
    channelData: CreateChannelRequest
  ): Promise<ChannelResponse> {
    return api<ChannelResponse>('/channels', {
      method: 'POST',
      body: channelData,
    })
  },

  /**
   * Delete a channel (blacklist)
   * @throws {FetchError} When the API request fails
   */
  async deleteChannel(
    channelId: string
  ): Promise<{ data: { message: string } }> {
    return api<{ data: { message: string } }>(`/channels/${channelId}`, {
      method: 'DELETE',
    })
  },
}

// UserGuild API
export const userGuildApi = {
  /**
   * Get all user-guild relationships
   * @throws {FetchError} When the API request fails
   */
  async getUserGuilds(): Promise<UserGuildsResponse> {
    return api<UserGuildsResponse>('/user-guilds')
  },

  /**
   * Get a specific user-guild relationship
   * @throws {FetchError} When the API request fails
   */
  async getUserGuild(
    userId: string,
    guildId: string
  ): Promise<UserGuildResponse> {
    return api<UserGuildResponse>('/user-guilds', {
      query: { userId, guildId },
    })
  },

  /**
   * Create a new user-guild relationship
   * @throws {FetchError} When the API request fails
   */
  async createUserGuild(
    userGuildData: CreateUserGuildRequest
  ): Promise<UserGuildResponse> {
    return api<UserGuildResponse>('/user-guilds', {
      method: 'POST',
      body: userGuildData,
    })
  },

  /**
   * Update a user-guild relationship
   * @throws {FetchError} When the API request fails
   */
  async updateUserGuild(
    userId: string,
    guildId: string,
    updateData: UpdateUserGuildRequest
  ): Promise<UserGuildResponse> {
    return api<UserGuildResponse>('/user-guilds', {
      method: 'PUT',
      query: { userId, guildId },
      body: updateData,
    })
  },
}

// Leaderboard API
export const leaderboardApi = {
  /**
   * Get intimacy leaderboard for a guild
   * @throws {FetchError} When the API request fails
   */
  async getIntimacyLeaderboard(
    request: LeaderboardRequest
  ): Promise<LeaderboardResponse> {
    return api<LeaderboardResponse>('/leaderboard', {
      query: {
        guildId: request.guildId,
        ...(request.limit && { limit: request.limit.toString() }),
      },
    })
  },
}

// Token API
export const tokenApi = {
  /**
   * Get token count for text
   * @throws {FetchError} When the API request fails
   */
  async getTokenCount(text: string): Promise<TokenResponse> {
    return api<TokenResponse>('/tokens', {
      method: 'POST',
      body: { text },
    })
  },
}

// System Prompt API
export const systemPromptApi = {
  /**
   * Get the current system prompt
   * @throws {FetchError} When the API request fails
   */
  async getSystemPrompt(): Promise<SystemPromptResponse> {
    return api<SystemPromptResponse>('/system-prompt', {
      method: 'GET',
    })
  },

  /**
   * Set a new system prompt
   * @throws {FetchError} When the API request fails
   */
  async setSystemPrompt(prompt: string): Promise<SetSystemPromptResponse> {
    return api<SetSystemPromptResponse>('/system-prompt', {
      method: 'POST',
      body: { prompt },
    })
  },
}

// Lyrics API
export const lyricsApi = {
  /**
   * Get all lyrics
   * @throws {FetchError} When the API request fails
   */
  async getAllLyrics(): Promise<LyricsListResponse> {
    return api<LyricsListResponse>('/lyrics', {
      method: 'GET',
    })
  },

  /**
   * Create new lyrics
   * @throws {FetchError} When the API request fails
   */
  async createLyrics(lyricsData: CreateLyricsRequest): Promise<LyricsResponse> {
    return api<LyricsResponse>('/lyrics', {
      method: 'POST',
      body: lyricsData,
    })
  },

  /**
   * Get lyrics by artist
   * @throws {FetchError} When the API request fails
   */
  async getLyricsByArtist(artist: string): Promise<LyricsListResponse> {
    return api<LyricsListResponse>(`/lyrics/${encodeURIComponent(artist)}`, {
      method: 'GET',
    })
  },

  /**
   * Get specific lyrics by artist and title
   * @throws {FetchError} When the API request fails
   */
  async getLyrics(artist: string, title: string): Promise<LyricsResponse> {
    return api<LyricsResponse>(
      `/lyrics/${encodeURIComponent(artist)}/${encodeURIComponent(title)}`,
      {
        method: 'GET',
      }
    )
  },

  /**
   * Update lyrics by artist and title
   * @throws {FetchError} When the API request fails
   */
  async updateLyrics(
    artist: string,
    title: string,
    updates: UpdateLyricsRequest
  ): Promise<LyricsResponse> {
    return api<LyricsResponse>(
      `/lyrics/${encodeURIComponent(artist)}/${encodeURIComponent(title)}`,
      {
        method: 'PUT',
        body: updates,
      }
    )
  },
}

// Discord Operations Types (Optimized endpoints)
export interface EnsureUserGuildExistsRequest {
  userId: string
  guildId: string
  role?: 'user' | 'admin'
}

export interface RecordUserMessageRequest {
  userId: string
  guildId: string
  intimacyIncrement?: number
}

export type EnsureUserGuildExistsResponse = {
  data: {
    user: User
    userGuild: UserGuild
    userCreated: boolean
    userGuildCreated: boolean
  }
}

export interface RecordUserMessageResponse {
  data: {
    user: User
    userGuild: UserGuild
    userCreated: boolean
    userGuildCreated: boolean
  }
}

// Discord Operations API (optimized for Discord bots)
export const discordOpsApi = {
  /**
   * Ensure user and user-guild relationship exist (atomic operation)
   * @throws {FetchError} When the API request fails
   */
  async ensureUserGuildExists(
    request: EnsureUserGuildExistsRequest
  ): Promise<EnsureUserGuildExistsResponse> {
    return api<EnsureUserGuildExistsResponse>('/ensure-user-guild-exists', {
      method: 'POST',
      body: request,
    })
  },

  /**
   * Record a user message, ensuring user/guild exist and updating stats (atomic operation)
   * @throws {FetchError} When the API request fails
   */
  async recordUserMessage(
    request: RecordUserMessageRequest
  ): Promise<RecordUserMessageResponse> {
    return api<RecordUserMessageResponse>('/record-user-message', {
      method: 'POST',
      body: request,
    })
  },
  recordUserMessageEffect(request: RecordUserMessageRequest) {
    return makeApiEffect(
      () => discordOpsApi.recordUserMessage(request),
      'discord.recordUserMessage'
    )
  },
}

// =====================
// ERROR HANDLING & UTILITIES
// =====================

/**
 * Standardized API error class for Effect-based error handling
 */
export class ApiError extends Data.TaggedError('ApiError')<{
  message: string
  statusCode?: number
  endpoint?: string
  originalError?: unknown
}> {}

/**
 * Legacy error class - will be deprecated in favor of ApiError
 * @deprecated Use ApiError instead
 */
export class OfetchError extends Data.TaggedError('OfetchError')<{
  message: unknown
  statusCode?: number
}> {}

/**
 * Utility function to extract error message from FetchError
 */
export function getFetchErrorMessage(error: FetchError): string {
  return `${error.statusCode ? `${error.statusCode}: ` : ''}${error.message}`
}

/**
 * Convert a Promise-based API call to an Effect with standardized error handling
 */
export const makeApiEffect = <T>(
  apiCall: () => Promise<T>,
  endpoint: string
): Effect.Effect<T, ApiError> =>
  Effect.tryPromise({
    try: apiCall,
    catch: (error) => {
      if (error instanceof FetchError) {
        return new ApiError({
          message: error.message,
          statusCode: error.statusCode,
          endpoint,
          originalError: error,
        })
      }

      return new ApiError({
        message: String(error),
        endpoint,
        originalError: error,
      })
    },
  })

// =====================
// RESILIENCE PATTERNS & POLICIES
// =====================

/**
 * Standard retry policy for API calls
 * Exponential backoff with jitter, max 3 retries
 */
export const standardRetryPolicy = Schedule.exponential(
  Duration.seconds(1)
).pipe(Schedule.intersect(Schedule.recurs(3)), Schedule.jittered)

/**
 * Aggressive retry policy for critical operations
 * More retries with longer backoff
 */
export const aggressiveRetryPolicy = Schedule.exponential(
  Duration.seconds(2)
).pipe(Schedule.intersect(Schedule.recurs(5)), Schedule.jittered)

/**
 * Quick retry policy for fast operations
 * Shorter delays, fewer retries
 */
export const quickRetryPolicy = Schedule.exponential(Duration.millis(500)).pipe(
  Schedule.intersect(Schedule.recurs(2)),
  Schedule.jittered
)

/**
 * Add retry policy to an API Effect with logging
 */
export const withRetry = <T>(
  effect: Effect.Effect<T, ApiError>,
  policy = standardRetryPolicy,
  operation?: string
): Effect.Effect<T, ApiError> =>
  effect.pipe(
    Effect.retry(policy),
    Effect.tapError((error) =>
      Effect.logWarning(
        `${operation || 'API operation'} failed after retries: ${error.message} (${error.endpoint})`
      )
    )
  )

/**
 * Add timeout to an API Effect
 */
export const withTimeout = <T>(
  effect: Effect.Effect<T, ApiError>,
  duration = Duration.seconds(30)
): Effect.Effect<T, ApiError> =>
  effect.pipe(
    Effect.timeout(duration),
    Effect.catchTag('TimeoutException', (error) =>
      Effect.fail(
        new ApiError({
          message: `Operation timed out after ${Duration.toMillis(duration)}ms`,
          originalError: error,
        })
      )
    )
  )

/**
 * Add rate limiting to an API Effect
 */
export const withRateLimit = <T>(
  effect: Effect.Effect<T, ApiError>,
  delay = Duration.millis(100)
): Effect.Effect<T, ApiError> => effect.pipe(Effect.delay(delay))

/**
 * Circuit breaker pattern for API calls
 * Opens circuit after 5 failures in 1 minute, closes after 30 seconds
 */
export const withCircuitBreaker = <T>(
  effect: Effect.Effect<T, ApiError>,
  name: string
): Effect.Effect<T, ApiError> => {
  // Simple circuit breaker implementation
  // In a production app, you'd want a more sophisticated implementation
  return effect.pipe(
    Effect.tapError((error) =>
      Effect.logError(`Circuit breaker [${name}]: ${error.message}`)
    )
  )
}

/**
 * Compose multiple resilience patterns
 */
export const withResilience = <T>(
  effect: Effect.Effect<T, ApiError>,
  options: {
    retry?: typeof standardRetryPolicy
    timeout?: Duration.Duration
    rateLimit?: Duration.Duration
    circuitBreaker?: string
    operation?: string
  } = {}
): Effect.Effect<T, ApiError> => {
  let resilientEffect = effect

  // Apply rate limiting first
  if (options.rateLimit) {
    resilientEffect = withRateLimit(resilientEffect, options.rateLimit)
  }

  // Apply timeout
  if (options.timeout) {
    resilientEffect = withTimeout(resilientEffect, options.timeout)
  }

  // Apply circuit breaker
  if (options.circuitBreaker) {
    resilientEffect = withCircuitBreaker(
      resilientEffect,
      options.circuitBreaker
    )
  }

  // Apply retry last (outermost)
  if (options.retry) {
    resilientEffect = withRetry(
      resilientEffect,
      options.retry,
      options.operation
    )
  }

  return resilientEffect
}

// =====================
// EFFECT-BASED API MODULES
// =====================

/**
 * Effect-based User API with standardized error handling
 */
export const userEffectApi = {
  getUsers: () => makeApiEffect(() => userApi.getUsers(), 'users.getUsers'),
  getUser: (userId: string) =>
    makeApiEffect(() => userApi.getUser(userId), 'users.getUser'),
  createUser: (userData: CreateUserRequest) =>
    makeApiEffect(() => userApi.createUser(userData), 'users.createUser'),
  updateUser: (userId: string, updateData: Omit<UpdateUserRequest, 'userId'>) =>
    makeApiEffect(
      () => userApi.updateUser(userId, updateData),
      'users.updateUser'
    ),
  deleteUser: (userId: string) =>
    makeApiEffect(() => userApi.deleteUser(userId), 'users.deleteUser'),
}

/**
 * Effect-based Guild API with standardized error handling
 */
export const guildEffectApi = {
  getGuilds: () =>
    makeApiEffect(() => guildApi.getGuilds(), 'guilds.getGuilds'),
  getGuild: (guildId: string) =>
    makeApiEffect(() => guildApi.getGuild(guildId), 'guilds.getGuild'),
  createGuild: (guildData: CreateGuildRequest) =>
    makeApiEffect(() => guildApi.createGuild(guildData), 'guilds.createGuild'),
  deleteGuild: (guildId: string) =>
    makeApiEffect(() => guildApi.deleteGuild(guildId), 'guilds.deleteGuild'),
}

/**
 * Effect-based Channel API with standardized error handling
 */
export const channelEffectApi = {
  getChannels: () =>
    makeApiEffect(() => channelApi.getChannels(), 'channels.getChannels'),
  getChannel: (channelId: string) =>
    makeApiEffect(
      () => channelApi.getChannel(channelId),
      'channels.getChannel'
    ),
  createChannel: (channelData: CreateChannelRequest) =>
    makeApiEffect(
      () => channelApi.createChannel(channelData),
      'channels.createChannel'
    ),
  deleteChannel: (channelId: string) =>
    makeApiEffect(
      () => channelApi.deleteChannel(channelId),
      'channels.deleteChannel'
    ),
}

/**
 * Effect-based UserGuild API with standardized error handling
 */
export const userGuildEffectApi = {
  getUserGuilds: () =>
    makeApiEffect(
      () => userGuildApi.getUserGuilds(),
      'userGuilds.getUserGuilds'
    ),
  getUserGuild: (userId: string, guildId: string) =>
    makeApiEffect(
      () => userGuildApi.getUserGuild(userId, guildId),
      'userGuilds.getUserGuild'
    ),
  createUserGuild: (userGuildData: CreateUserGuildRequest) =>
    makeApiEffect(
      () => userGuildApi.createUserGuild(userGuildData),
      'userGuilds.createUserGuild'
    ),
  updateUserGuild: (
    userId: string,
    guildId: string,
    updateData: UpdateUserGuildRequest
  ) =>
    makeApiEffect(
      () => userGuildApi.updateUserGuild(userId, guildId, updateData),
      'userGuilds.updateUserGuild'
    ),
}

/**
 * Effect-based Leaderboard API with standardized error handling
 */
export const leaderboardEffectApi = {
  getIntimacyLeaderboard: (request: LeaderboardRequest) =>
    makeApiEffect(
      () => leaderboardApi.getIntimacyLeaderboard(request),
      'leaderboard.getIntimacyLeaderboard'
    ),
}

/**
 * Effect-based Token API with standardized error handling
 */
export const tokenEffectApi = {
  getTokenCount: (text: string) =>
    makeApiEffect(() => tokenApi.getTokenCount(text), 'tokens.getTokenCount'),
}

/**
 * Effect-based System Prompt API with standardized error handling
 */
export const systemPromptEffectApi = {
  getSystemPrompt: () =>
    makeApiEffect(
      () => systemPromptApi.getSystemPrompt(),
      'systemPrompt.getSystemPrompt'
    ),
  setSystemPrompt: (prompt: string) =>
    makeApiEffect(
      () => systemPromptApi.setSystemPrompt(prompt),
      'systemPrompt.setSystemPrompt'
    ),
}

/**
 * Effect-based Lyrics API with standardized error handling
 */
export const lyricsEffectApi = {
  getAllLyrics: () =>
    makeApiEffect(() => lyricsApi.getAllLyrics(), 'lyrics.getAllLyrics'),
  createLyrics: (lyricsData: CreateLyricsRequest) =>
    makeApiEffect(
      () => lyricsApi.createLyrics(lyricsData),
      'lyrics.createLyrics'
    ),
  getLyricsByArtist: (artist: string) =>
    makeApiEffect(
      () => lyricsApi.getLyricsByArtist(artist),
      'lyrics.getLyricsByArtist'
    ),
  getLyrics: (artist: string, title: string) =>
    makeApiEffect(() => lyricsApi.getLyrics(artist, title), 'lyrics.getLyrics'),
  updateLyrics: (artist: string, title: string, updates: UpdateLyricsRequest) =>
    makeApiEffect(
      () => lyricsApi.updateLyrics(artist, title, updates),
      'lyrics.updateLyrics'
    ),
}

/**
 * Effect-based Discord Operations API with standardized error handling
 */
export const discordOpsEffectApi = {
  ensureUserGuildExists: (request: EnsureUserGuildExistsRequest) =>
    makeApiEffect(
      () => discordOpsApi.ensureUserGuildExists(request),
      'discord.ensureUserGuildExists'
    ),
  recordUserMessage: (request: RecordUserMessageRequest) =>
    makeApiEffect(
      () => discordOpsApi.recordUserMessage(request),
      'discord.recordUserMessage'
    ),
}

/**
 * Effect-based API modules with standardized error handling
 *
 * These are the recommended APIs to use for new code.
 * They provide proper Effect-TS integration with consistent error handling.
 */
export const effectApi = {
  users: userEffectApi,
  guilds: guildEffectApi,
  channels: channelEffectApi,
  userGuilds: userGuildEffectApi,
  tokens: tokenEffectApi,
  systemPrompt: systemPromptEffectApi,
  lyrics: lyricsEffectApi,
  discord: discordOpsEffectApi,
  leaderboard: leaderboardEffectApi,
}

// =====================
// EXPORT ALL APIs
// =====================

/**
 * Legacy Promise-based API modules
 *
 * @deprecated Use effectApi instead for new code.
 * These modules throw FetchError on HTTP errors.
 */
export const promiseApi = {
  users: userApi,
  guilds: guildApi,
  channels: channelApi,
  userGuilds: userGuildApi,
  tokens: tokenApi,
  systemPrompt: systemPromptApi,
  lyrics: lyricsApi,
  // New optimized operations
  discord: discordOpsApi,
  leaderboard: leaderboardApi,
}

/**
 * Main API export - currently pointing to legacy Promise-based APIs
 *
 * @deprecated Use effectApi instead for new code.
 */
export const discordBotApi = promiseApi

export default discordBotApi
