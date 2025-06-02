defmodule TetoBot.Users do
  alias Nostrum.Snowflake
  alias Ecto.Multi

  alias TetoBot.Repo
  alias TetoBot.Users.{User, UserGuild}

  @doc """
  Gets the last interaction timestamp for a user in a specific guild.
  Returns {:error, :not_found} if the user doesn't exist in that guild.

  ## Examples
      iex> TetoBot.Users.get_last_interaction(12345, 67890)
      {:ok, ~U[2025-05-31 10:30:00Z]}

      iex> TetoBot.Users.get_last_interaction(12345, 99999)
      {:error, :not_found}
  """
  @spec get_last_interaction(integer(), integer()) :: {:ok, DateTime.t()} | {:error, :not_found}
  def get_last_interaction(guild_id, user_id) do
    case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
      nil -> {:error, :not_found}
      %UserGuild{last_interaction: nil} -> {:error, :not_found}
      %UserGuild{last_interaction: datetime} -> {:ok, datetime}
    end
  end

  @doc """
  Updates the last interaction timestamp for a user in a specific guild.
  Creates the user and user_guild records if they don't exist.
  Should be called when a user chats or uses commands to track activity.

  ## Examples
      iex> TetoBot.Users.update_last_interaction(12345, 67890)
      {:ok, %UserGuild{}}

      iex> TetoBot.Users.update_last_interaction(invalid_guild_id, invalid_user_id)
      {:error, %Ecto.Changeset{}}
  """
  @spec update_last_interaction(Snowflake.t(), Snowflake.t()) ::
          {:ok, UserGuild} | {:error, Ecto.Changeset.t()}
  def update_last_interaction(guild_id, user_id) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.insert(
      :user,
      User.changeset(%User{user_id: user_id}, %{}),
      on_conflict: [set: [updated_at: now]],
      conflict_target: :user_id
    )
    |> Multi.insert(
      :user_guild,
      UserGuild.changeset(%UserGuild{}, %{
        user_id: user_id,
        guild_id: guild_id,
        last_interaction: now
      }),
      on_conflict: [set: [last_interaction: now, updated_at: now]],
      conflict_target: [:user_id, :guild_id]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user_guild: user_guild}} -> {:ok, user_guild}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :user_guild, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Same as update_last_interaction/2 but raises on error.
  """
  @spec update_last_interaction!(Snowflake.t(), Snowflake.t()) :: UserGuild
  def update_last_interaction!(guild_id, user_id) do
    case update_last_interaction(guild_id, user_id) do
      {:ok, user_guild} -> user_guild
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end

  @doc """
  Checks if a user can use the feed command based on their last_feed timestamp in a specific guild.
  """
  @spec check_feed_cooldown(Snowflake.t(), Snowflake.t()) :: {:ok, :allowed} | {:error, integer()}
  def check_feed_cooldown(guild_id, user_id) do
    case Repo.get_by(UserGuild, guild_id: guild_id, user_id: user_id) do
      nil ->
        {:ok, :allowed}

      %UserGuild{last_feed: nil} ->
        {:ok, :allowed}

      %UserGuild{last_feed: last_feed} ->
        now = DateTime.utc_now()
        today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

        if DateTime.compare(last_feed, today_start) == :lt do
          {:ok, :allowed}
        else
          tomorrow_start = DateTime.add(today_start, 1, :day)
          time_left = DateTime.diff(tomorrow_start, now, :second)
          {:error, time_left}
        end
    end
  end

  @doc """
  Sets the last_feed timestamp for a user in a specific guild.
  """
  @spec set_feed_cooldown(Snowflake.t(), Snowflake.t()) ::
          {:ok, UserGuild} | {:error, Ecto.Changeset.t()}
  def set_feed_cooldown(guild_id, user_id) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.insert(
      :user,
      User.changeset(%User{user_id: user_id}, %{}),
      on_conflict: [set: [updated_at: now]],
      conflict_target: :user_id
    )
    |> Multi.insert(
      :user_guild,
      UserGuild.changeset(%UserGuild{}, %{
        user_id: user_id,
        guild_id: guild_id,
        last_feed: now
      }),
      on_conflict: [set: [last_feed: now, updated_at: now]],
      conflict_target: [:user_id, :guild_id]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user_guild: user_guild}} -> {:ok, user_guild}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :user_guild, changeset, _} -> {:error, changeset}
    end
  end
end
