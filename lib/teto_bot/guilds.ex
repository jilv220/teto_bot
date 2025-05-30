defmodule TetoBot.Guilds do
  require Nostrum.Snowflake

  alias Nostrum.Snowflake
  alias TetoBot.Guilds.Guild

  @repo Application.compile_env(:teto_bot, :repo, TetoBot.Repo)

  @spec guild_create(Snowflake.t()) :: {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  @doc """
  A guild added our app
  Insert a new guild record `guilds` table
  """
  def guild_create(guild_id) when Snowflake.is_snowflake(guild_id) do
    %Guild{}
    |> Guild.changeset(%{guild_id: guild_id})
    |> @repo.insert([])
  end

  @spec guild_delete(Snowflake.t()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @doc """
  A guild removed our app
  Remove the record from `guilds` table
  """
  def guild_delete(guild_id) when Snowflake.is_snowflake(guild_id) do
    case @repo.get_by(Guild, [guild_id: guild_id], []) do
      nil ->
        {:error, :not_found}

      guild ->
        @repo.delete(guild, [])
    end
  end
end
