defmodule TetoBot.Guilds.Cache do
  use TetoBot.Cache.Snowflake, entity_type: "guild"
  @behaviour TetoBot.Guilds.CacheBehaviour
end
