defmodule TetoBot.Channels.Cache do
  use TetoBot.Cache.Snowflake, entity_type: "channel"
  @behaviour TetoBot.Channels.CacheBehaviour
end
