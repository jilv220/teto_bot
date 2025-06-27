import {
  ChannelType,
  type ChatInputCommandInteraction,
  MessageFlags,
  SlashCommandBuilder,
} from 'discord.js'
import { Effect, Either, Runtime } from 'effect'
import type { MainLive } from '../services'
import { type ApiError, ApiService, effectApi } from '../services/api'
import { hasManageChannelsPermissionFromInteraction } from '../utils/permissions'

export const data = new SlashCommandBuilder()
  .setName('blacklist')
  .setDescription(
    'Remove a channel from the whitelist (requires Manage Channels permission)'
  )
  .addChannelOption((option) =>
    option
      .setName('channel')
      .setDescription('The channel to remove from the whitelist')
      .setRequired(true)
      .addChannelTypes(ChannelType.GuildText)
  )

/**
 * Build appropriate error message based on ApiError
 */
function buildErrorMessage(error: ApiError, channelId: string): string {
  if (error.statusCode === 404) {
    return `Channel <#${channelId}> was not found in the whitelist.`
  }

  return `Failed to blacklist channel <#${channelId}>: ${error.message}`
}

/**
 * Effect-based blacklist operation
 */
const blacklistChannelEffect = (
  channelId: string,
  userId: string,
  guildId: string
) =>
  Effect.gen(function* () {
    const apiService = yield* ApiService
    const effectApi = apiService.effectApi

    // Ensure user-guild relationship exists
    yield* effectApi.discord.ensureUserGuildExists({
      userId,
      guildId,
    })

    // Remove channel from whitelist (delete from database)
    const result = yield* effectApi.channels.deleteChannel(channelId)

    return result
  }).pipe(
    Effect.tapError((error) =>
      Effect.logError(
        `Failed to blacklist channel ${channelId}: ${error.message}`
      )
    )
  )

export async function execute(
  runtime: Runtime.Runtime<never>,
  live: typeof MainLive,
  interaction: ChatInputCommandInteraction
) {
  if (!interaction.guildId) {
    await interaction.reply({
      content: 'This command can only be used in a server.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  // Check permissions
  if (!hasManageChannelsPermissionFromInteraction(interaction)) {
    await interaction.reply({
      content: 'You need the "Manage Channels" permission to use this command.',
      flags: MessageFlags.Ephemeral,
    })
    return
  }

  const channel = interaction.options.getChannel('channel', true)

  // Convert Effect to Either and run it
  const program = blacklistChannelEffect(
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
      content: `Channel <#${channel.id}> has been removed from the whitelist.`,
      flags: MessageFlags.Ephemeral,
    })
  }
}
