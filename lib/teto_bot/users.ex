defmodule TetoBot.Users do
  alias Nostrum.Snowflake
  alias Ecto.Multi

  alias TetoBot.Repo
  alias TetoBot.Users.User

  @doc """
  Gets the last interaction timestamp for a user.
  Returns {:error, :not_found} if the user doesn't exist.

  ## Examples
      iex> TetoBot.Users.get_last_interaction(67890)
      {:ok, ~U[2025-05-31 10:30:00Z]}

      iex> TetoBot.Users.get_last_interaction(99999)
      {:error, :not_found}
  """
  @spec get_last_interaction(integer()) :: {:ok, DateTime.t()} | {:error, :not_found}
  def get_last_interaction(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      %User{last_interaction: nil} -> {:error, :not_found}
      %User{last_interaction: datetime} -> {:ok, datetime}
    end
  end

  @doc """
  Updates the last interaction timestamp for a user.
  Creates the user record if it doesn't exist.
  Should be called when a user chats or uses commands to track activity.

  ## Examples
      iex> TetoBot.Users.update_last_interaction(67890)
      {:ok, %User{}}

      iex> TetoBot.Users.update_last_interaction(invalid_user_id)
      {:error, %Ecto.Changeset{}}
  """

  @spec update_last_interaction(Snowflake.t(), Snowflake.t()) ::
          {:ok, User} | {:error, Ecto.Changeset.t()}
  def update_last_interaction(guild_id, user_id) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.insert(
      :user,
      User.changeset(%User{user_id: user_id}, %{last_interaction: now}),
      on_conflict: [set: [last_interaction: now, updated_at: now]],
      conflict_target: :user_id
    )
    |> Multi.run(:user_guild, fn _repo, _changes ->
      result =
        Repo.insert_all(
          "user_guilds",
          [%{user_id: user_id, guild_id: guild_id, inserted_at: now, updated_at: now}],
          on_conflict: :nothing,
          conflict_target: [:user_id, :guild_id]
        )

      {:ok, result}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, :user_guild, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Same as update_last_interaction/1 but raises on error.
  """
  @spec update_last_interaction!(Snowflake.t(), Snowflake.t()) :: User
  def update_last_interaction!(guild_id, user_id) do
    case update_last_interaction(guild_id, user_id) do
      {:ok, user} -> user
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset
    end
  end
end
