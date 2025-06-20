import { Data, Effect } from 'effect'
import { FetchError, type FetchOptions, ofetch } from 'ofetch'
import { appConfig } from './config'

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
    console.error(`API Error: ${response.status} - ${response.statusText}`)
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

// Error Types
export interface ApiError {
  error: {
    code: number
    message: string
  }
}

export interface ValidationError {
  error: {
    message: string
    issues: Array<{
      path: string[]
      message: string
      code: string
    }>
  }
}

// Response union types
export type ApiResponse<T> = T | ApiError | ValidationError

// =====================
// API CLIENT FUNCTIONS
// =====================

// User API
export const userApi = {
  /**
   * Get all users
   */
  async getUsers(): Promise<ApiResponse<UsersResponse>> {
    return api<UsersResponse>('/users')
  },

  /**
   * Get a specific user by ID
   */
  async getUser(userId: string): Promise<UserResponse> {
    return api<UserResponse>(`/users/${userId}`)
  },

  /**
   * Create a new user
   */
  async createUser(
    userData: CreateUserRequest
  ): Promise<ApiResponse<UserResponse>> {
    return api<UserResponse>('/users', {
      method: 'POST',
      body: userData,
    })
  },

  /**
   * Update an existing user
   */
  async updateUser(
    userId: string,
    updateData: Omit<UpdateUserRequest, 'userId'>
  ): Promise<ApiResponse<UserResponse>> {
    return api<UserResponse>(`/users/${userId}`, {
      method: 'PUT',
      body: updateData,
    })
  },

  /**
   * Delete a user
   */
  async deleteUser(
    userId: string
  ): Promise<ApiResponse<{ data: { message: string } }>> {
    return api<{ data: { message: string } }>(`/users/${userId}`, {
      method: 'DELETE',
    })
  },
}

// Guild API
export const guildApi = {
  /**
   * Get all guilds
   */
  async getGuilds(): Promise<ApiResponse<GuildsResponse>> {
    return api<GuildsResponse>('/guilds')
  },

  /**
   * Get a specific guild by ID
   */
  async getGuild(guildId: string): Promise<ApiResponse<GuildResponse>> {
    return api<GuildResponse>(`/guilds/${guildId}`)
  },

  /**
   * Create a new guild
   */
  async createGuild(guildData: CreateGuildRequest): Promise<GuildResponse> {
    return api<GuildResponse>('/guilds', {
      method: 'POST',
      body: guildData,
    })
  },

  /**
   * Delete a guild
   */
  deleteGuild(guildId: string): Promise<{ data: { message: string } }> {
    return api<{ data: { message: string } }>(`/guilds/${guildId}`, {
      method: 'DELETE',
    })
  },

  deleteGuildEffect: (guildId: string) =>
    Effect.tryPromise({
      try: () => guildApi.deleteGuild(guildId),
      catch: (error) => Effect.fail(error),
    }).pipe(Effect.tapError((error) => Effect.logError(error))),
}

// Channel API
export const channelApi = {
  /**
   * Get all channels
   */
  async getChannels(): Promise<ApiResponse<ChannelsResponse>> {
    return api<ChannelsResponse>('/channels')
  },

  /**
   * Get a specific channel by ID
   */
  async getChannel(channelId: string): Promise<ApiResponse<ChannelResponse>> {
    return api<ChannelResponse>(`/channels/${channelId}`)
  },

  /**
   * Create a new channel
   */
  async createChannel(
    channelData: CreateChannelRequest
  ): Promise<ApiResponse<ChannelResponse>> {
    return api<ChannelResponse>('/channels', {
      method: 'POST',
      body: channelData,
    })
  },

  /**
   * Delete a channel (blacklist)
   */
  async deleteChannel(
    channelId: string
  ): Promise<ApiResponse<{ data: { message: string } }>> {
    return api<{ data: { message: string } }>(`/channels/${channelId}`, {
      method: 'DELETE',
    })
  },
}

// UserGuild API
export const userGuildApi = {
  /**
   * Get all user-guild relationships
   */
  async getUserGuilds(): Promise<ApiResponse<UserGuildsResponse>> {
    return api<UserGuildsResponse>('/user-guilds')
  },

  /**
   * Get a specific user-guild relationship
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
   */
  async createUserGuild(
    userGuildData: CreateUserGuildRequest
  ): Promise<ApiResponse<UserGuildResponse>> {
    return api<UserGuildResponse>('/user-guilds', {
      method: 'POST',
      body: userGuildData,
    })
  },

  /**
   * Update a user-guild relationship
   */
  async updateUserGuild(
    userId: string,
    guildId: string,
    updateData: UpdateUserGuildRequest
  ): Promise<ApiResponse<UserGuildResponse>> {
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
   */
  async getIntimacyLeaderboard(
    request: LeaderboardRequest
  ): Promise<ApiResponse<LeaderboardResponse>> {
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
   */
  async getTokenCount(text: string): Promise<ApiResponse<TokenResponse>> {
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
   */
  async getSystemPrompt(): Promise<SystemPromptResponse> {
    return api<SystemPromptResponse>('/system-prompt', {
      method: 'GET',
    })
  },

  /**
   * Set a new system prompt
   */
  async setSystemPrompt(
    prompt: string
  ): Promise<ApiResponse<SetSystemPromptResponse>> {
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
   */
  async getAllLyrics(): Promise<LyricsListResponse> {
    return api<LyricsListResponse>('/lyrics', {
      method: 'GET',
    })
  },

  /**
   * Create new lyrics
   */
  async createLyrics(lyricsData: CreateLyricsRequest): Promise<LyricsResponse> {
    return api<LyricsResponse>('/lyrics', {
      method: 'POST',
      body: lyricsData,
    })
  },

  /**
   * Get lyrics by artist
   */
  async getLyricsByArtist(artist: string): Promise<LyricsListResponse> {
    return api<LyricsListResponse>(`/lyrics/${encodeURIComponent(artist)}`, {
      method: 'GET',
    })
  },

  /**
   * Get specific lyrics by artist and title
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
    return Effect.tryPromise({
      try: () => discordOpsApi.recordUserMessage(request),
      catch: (error) => {
        if (error instanceof FetchError)
          return new OfetchError({
            message: error.message,
            statusCode: error.statusCode,
          })

        return new OfetchError({
          message: error,
        })
      },
    })
  },
}

// =====================
// UTILITY FUNCTIONS
// =====================
export class OfetchError extends Data.TaggedError('OfetchError')<{
  message: unknown
  statusCode?: number
}> {}

/**
 * Type guard to check if response is an error
 */
export function isApiError(response: unknown): response is ApiError {
  return !!(response && typeof response === 'object' && 'error' in response)
}

/**
 * Type guard to check if response is a validation error
 */
export function isValidationError(
  response: unknown
): response is ValidationError {
  return (
    isApiError(response) &&
    response.error &&
    typeof response.error === 'object' &&
    'issues' in response.error
  )
}

/**
 * Extract error message from API response
 */
export function getErrorMessage(response: ApiError | ValidationError): string {
  if (isValidationError(response)) {
    return response.error.issues
      .map((issue) => `${issue.path.join('.')}: ${issue.message}`)
      .join(', ')
  }
  return response.error.message
}

// =====================
// EXPORT ALL APIs
// =====================

export const discordBotApi = {
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

export default discordBotApi
