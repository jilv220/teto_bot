defmodule TetoBot.Guilds do
  @moduledoc """
  The Guilds domain.
  """
  use Ash.Domain

  alias TetoBot.Guilds.Guild

  resources do
    resource Guild do
      define :guild_ids, action: :guild_ids
      define :create_guild, args: [:guild_id], action: :create_guild
      define :delete_guild, args: [:guild_id], action: :delete_guild
      define :member_check, args: [:guild_id], action: :member_check
      define :members, args: [:guild_id], action: :members
      define :warm_cache, action: :warm_cache
      define :cache_stats, action: :cache_stats
    end
  end
end
