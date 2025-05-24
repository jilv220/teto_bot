defmodule TetoBot.Channels do
  @moduledoc """
  The context for managing Channels.
  """
  require Nostrum.Snowflake

  alias Nostrum.Snowflake
  alias TetoBot.Repo
  alias TetoBot.Channels.Channel

  @doc """
  Whitelists a channel by its ID.

  Inserts a new channel record into the database.

  ## Parameters
    - `channel_id`: The ID of the channel to whitelist.

  ## Returns
    - `{:ok, %TetoBot.Channel{}}` if the channel was successfully whitelisted.
    - `{:error, %Ecto.Changeset{}}` if there was an error during whitelisting (e.g., already exists, validation error).
  """
  def whitelist_channel(channel_id) when Snowflake.is_snowflake(channel_id) do
    %Channel{}
    |> Channel.changeset(%{channel_id: channel_id})
    |> Repo.insert()
  end

  @doc """
  Removes a channel from the whitelist (effectively blacklisting it).

  Deletes the channel record from the database.

  ## Parameters
    - `channel_id_str`: The string ID of the channel to remove from the whitelist.

  ## Returns
    - `{:ok, %TetoBot.Channel{}}` if the channel was successfully removed.
    - `{:error, :not_found}` if the channel was not found in the whitelist.
    - `{:error, %Ecto.Changeset{}}` for other deletion errors (less common for simple deletes).
  """
  def blacklist_channel(channel_id) when Snowflake.is_snowflake(channel_id) do
    case Repo.get_by(Channel, channel_id: channel_id) do
      nil ->
        {:error, :not_found}

      channel ->
        Repo.delete(channel)
    end
  end

  # @doc """
  # Checks if a channel is whitelisted.
  #
  # ## Parameters
  #   - `channel_id`: The Nostrum.Snowflake ID of the channel.
  #
  # ## Returns
  #   - `true` if the channel is whitelisted.
  #   - `false` otherwise.
  # """
  @spec whitelisted?(Snowflake.t()) :: boolean()
  def whitelisted?(channel_id) when Snowflake.is_snowflake(channel_id) do
    case Repo.get_by(Channel, channel_id: channel_id) do
      nil -> false
      _channel -> true
    end
  end

  def whitelisted?(_), do: false
end
