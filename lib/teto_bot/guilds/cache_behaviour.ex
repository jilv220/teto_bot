defmodule TetoBot.Guilds.CacheBehaviour do
  @moduledoc """
  Defines the behaviour for the Guilds cache.
  """
  alias Nostrum.Snowflake

  @callback add(Snowflake.t()) :: :ok
  @callback remove(Snowflake.t()) :: :ok
  @callback exists?(Snowflake.t()) :: boolean()
end
