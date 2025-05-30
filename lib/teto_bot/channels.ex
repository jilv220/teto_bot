defmodule TetoBot.Channels do
  @moduledoc """
  The context for managing Channels.
  """
  require Nostrum.Snowflake

  alias Nostrum.Snowflake
  alias TetoBot.Channels
  alias TetoBot.Channels.Channel

  @repo Application.compile_env(:teto_bot, :repo, TetoBot.Repo)

  @doc """
  Whitelists a channel by its ID.
  Inserts a new channel record into the database.
  """
  def whitelist_channel(channel_id) when Snowflake.is_snowflake(channel_id) do
    result =
      %Channel{}
      |> Channel.changeset(%{channel_id: channel_id})
      |> @repo.insert([])

    case result do
      {:ok, _channel} ->
        Channels.Cache.add(channel_id)
        result

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Removes a channel from the whitelist (effectively blacklisting it).
  Deletes the channel record from the database.
  """
  def blacklist_channel(channel_id) when Snowflake.is_snowflake(channel_id) do
    case @repo.get_by(Channel, [channel_id: channel_id], []) do
      nil ->
        {:error, :not_found}

      channel ->
        result = @repo.delete(channel, [])

        case result do
          {:ok, _channel} ->
            Channels.Cache.remove(channel_id)
            result

          {:error, _changeset} = error ->
            error
        end
    end
  end

  @doc """
  Checks if a channel is whitelisted.
  """
  @spec whitelisted?(Snowflake.t()) :: boolean()
  def whitelisted?(channel_id) when Snowflake.is_snowflake(channel_id) do
    case Channels.Cache.exists?(channel_id) do
      true ->
        true

      false ->
        case @repo.get_by(Channel, [channel_id: channel_id], []) do
          nil ->
            false

          _ ->
            Channels.Cache.add(channel_id)
            true
        end
    end
  end

  def whitelisted?(_), do: false
end
