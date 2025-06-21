import {
  ChannelType,
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import { ApiService, type MainLive } from '../services'
import type { ApiError } from '../services/api/client'
import { hasManageChannelsPermission } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('whitelist')
  .setDescription(
    'Whitelist a channel for the bot to operate in (requires Manage Channels permission)'
  )
  .addChannelOption((option) =>
    option
      .setName('channel')
      .setDescription('The channel to whitelist')
      .setRequired(true)
      .addChannelTypes(ChannelType.GuildText)
  )

/**
 * Build appropriate error message based on ApiError
 */
function buildErrorMessage(error: ApiError, channelId: string): string {
  // Check for "conflict" errors (409 status)
  if (error.statusCode === 409) {
    return `Channel <#${channelId}> is already whitelisted.`
  }

  return `Failed to whitelist channel <#${channelId}>: ${error.message}`
}

/**
 * Effect-based whitelist operation
 */
const whitelistChannelEffect = (
  channelId: string,
  userId: string,
  guildId: string
): Effect.Effect<void, ApiError, ApiService> =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    // Ensure user-guild relationship exists
    yield* effectApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    // Add channel to whitelist (create in database)
    yield* effectApi.channels.createChannel({
      channelId,
      guildId,
    })
  }).pipe(
    Effect.tapError((error) =>
      Effect.logError(
        `Failed to whitelist channel ${channelId}: ${error.message}`
      )
    )
  )

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  // Check permissions
  if (!hasManageChannelsPermission(interaction)) {
    await interaction.reply({
      content: 'You need the "Manage Channels" permission to use this command.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const channel = interaction.options.getChannel('channel', true)

  if (!interaction.guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Convert Effect to Either and run it
  const program = whitelistChannelEffect(
    channel.id,
    interaction.user.id,
    interaction.guildId
  ).pipe(Effect.either, Effect.provide(live))
  const result = await Runtime.runPromise(runtime)(program)

  // Handle Either result
  if (Either.isLeft(result)) {
    // Error case
    const errorMessage = buildErrorMessage(result.left, channel.id)
    await interaction.reply({
      content: errorMessage,
      flags: MessageFlags.Ephemeral,
    })
  } else {
    // Success case
    await interaction.reply({
      content: `Channel <#${channel.id}> whitelisted successfully!`,
      flags: MessageFlags.Ephemeral,
    })
  }
}
