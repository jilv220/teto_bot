defmodule TetoBot.Channels do
  @moduledoc """
  The Channels domain.
  """
  use Ash.Domain

  alias TetoBot.Channels.Channel

  resources do
    resource Channel do
      define :whitelist_channel, args: [:guild_id, :channel_id], action: :whitelist_channel
      define :blacklist_channel, args: [:guild_id, :channel_id], action: :blacklist_channel
      define :whitelisted?, args: [:channel_id], action: :whitelisted_check
      define :cache_stats, action: :cache_stats
    end
  end
end
