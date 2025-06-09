defmodule TetoBot.Accounts.UserGuild do
  @moduledoc """
  Represents a user's membership in a guild with intimacy tracking.
  """

  require Logger
  require Ash.Query
  require Nostrum.Snowflake

  alias Nostrum.Snowflake

  use Ash.Resource,
    domain: TetoBot.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_guilds"
    repo TetoBot.Repo
  end

  actions do
    # Add default CRUD actions
    defaults [:read, :destroy, create: :*, update: :*]

    action :create_membership, :struct do
      argument :user_id, :integer, allow_nil?: false
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id
        guild_id = input.arguments.guild_id

        case {Snowflake.is_snowflake(user_id), Snowflake.is_snowflake(guild_id)} do
          {true, true} ->
            __MODULE__
            |> Ash.Changeset.for_create(:create, %{
              user_id: user_id,
              guild_id: guild_id,
              intimacy: 0
            })
            |> Ash.create()

          _ ->
            {:error, :invalid_id}
        end
      end
    end

    action :get_membership, :struct do
      argument :user_id, :integer, allow_nil?: false
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id
        guild_id = input.arguments.guild_id

        __MODULE__
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(user_id == ^user_id and guild_id == ^guild_id)
        |> Ash.read_one()
      end
    end

    action :update_intimacy, :struct do
      argument :user_id, :integer, allow_nil?: false
      argument :guild_id, :integer, allow_nil?: false
      argument :intimacy, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id
        guild_id = input.arguments.guild_id
        intimacy = input.arguments.intimacy

        case __MODULE__
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(user_id == ^user_id and guild_id == ^guild_id)
             |> Ash.read_one() do
          {:ok, user_guild} ->
            user_guild
            |> Ash.Changeset.for_update(:update, %{intimacy: intimacy})
            |> Ash.update()

          {:ok, nil} ->
            {:error, :not_found}

          error ->
            error
        end
      end
    end

    action :update_last_message, :struct do
      argument :user_id, :integer, allow_nil?: false
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id
        guild_id = input.arguments.guild_id
        now = DateTime.utc_now()

        case __MODULE__
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(user_id == ^user_id and guild_id == ^guild_id)
             |> Ash.read_one() do
          {:ok, user_guild} ->
            user_guild
            |> Ash.Changeset.for_update(:update, %{last_message_at: now})
            |> Ash.update()

          {:ok, nil} ->
            # Create the membership if it doesn't exist
            __MODULE__
            |> Ash.Changeset.for_create(:create, %{
              user_id: user_id,
              guild_id: guild_id,
              intimacy: 0,
              last_message_at: now
            })
            |> Ash.create()

          error ->
            error
        end
      end
    end

    action :update_last_feed, :struct do
      argument :user_id, :integer, allow_nil?: false
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id
        guild_id = input.arguments.guild_id
        now = DateTime.utc_now()

        case __MODULE__
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(user_id == ^user_id and guild_id == ^guild_id)
             |> Ash.read_one() do
          {:ok, user_guild} ->
            user_guild
            |> Ash.Changeset.for_update(:update, %{last_feed: now})
            |> Ash.update()

          {:ok, nil} ->
            {:error, :not_found}

          error ->
            error
        end
      end
    end

    action :get_guild_members, {:array, :struct} do
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id

        __MODULE__
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(guild_id == ^guild_id)
        |> Ash.read()
      end
    end

    action :get_inactive_members, {:array, :struct} do
      argument :guild_id, :integer, allow_nil?: false
      argument :threshold, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id
        threshold_ms = input.arguments.threshold
        threshold_datetime = DateTime.from_unix!(threshold_ms, :millisecond)

        __MODULE__
        |> Ash.Query.for_read(:read)
        |> Ash.Query.filter(guild_id == ^guild_id)
        |> Ash.Query.filter(
          is_nil(last_message_at) or last_message_at < ^threshold_datetime or
            is_nil(last_feed) or last_feed < ^threshold_datetime
        )
        |> Ash.read()
      end
    end

    action :apply_decay, :integer do
      argument :guild_id, :integer, allow_nil?: false
      argument :decay_amount, :integer, allow_nil?: false
      argument :minimum_intimacy, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id
        decay_amount = input.arguments.decay_amount
        minimum_intimacy = input.arguments.minimum_intimacy

        # Get all members for this guild that are above minimum intimacy
        case __MODULE__
             |> Ash.Query.for_read(:read)
             |> Ash.Query.filter(guild_id == ^guild_id and intimacy >= ^minimum_intimacy)
             |> Ash.read() do
          {:ok, members} ->
            updated_count = apply_decay_to_members(members, decay_amount, minimum_intimacy)
            {:ok, updated_count}

          error ->
            error
        end
      end
    end
  end

  validations do
    validate numericality(:intimacy, greater_than_or_equal_to: 0)
  end

  attributes do
    # Composite primary key - database stores as bigint
    attribute :user_id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :guild_id, :integer, primary_key?: true, allow_nil?: false, public?: true

    # Intimacy and activity tracking - matches existing schema
    attribute :intimacy, :integer, default: 0, allow_nil?: false, public?: true
    attribute :last_message_at, :utc_datetime, public?: true
    attribute :last_feed, :utc_datetime, public?: true
    attribute :daily_message_count, :integer, default: 0, allow_nil?: false, public?: true

    # Default Ecto timestamps
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, TetoBot.Accounts.User do
      source_attribute :user_id
      destination_attribute :user_id
    end

    belongs_to :guild, TetoBot.Guilds.Guild do
      source_attribute :guild_id
      destination_attribute :guild_id
    end
  end

  calculations do
    calculate :tier_name, :string, expr(fragment("CASE
          WHEN ? >= 1000 THEN 'Husband'
          WHEN ? >= 500 THEN 'Best Friend'
          WHEN ? >= 200 THEN 'Close Friend'
          WHEN ? >= 101 THEN 'Good Friend'
          WHEN ? >= 51 THEN 'Friend'
          WHEN ? >= 21 THEN 'Buddy'
          WHEN ? >= 11 THEN 'Acquaintance'
          WHEN ? >= 5 THEN 'Familiar Face'
          ELSE 'Stranger'
        END", intimacy, intimacy, intimacy, intimacy, intimacy, intimacy, intimacy, intimacy))

    calculate :is_inactive, :boolean, expr(is_nil(last_message_at) and is_nil(last_feed))
  end

  identities do
    identity :unique_user_guild, [:user_id, :guild_id]
  end

  # Private helper function for decay logic
  defp apply_decay_to_members(members, decay_amount, minimum_intimacy) do
    Enum.reduce(members, 0, fn member, count ->
      new_intimacy = max(member.intimacy - decay_amount, minimum_intimacy)

      if new_intimacy != member.intimacy do
        case member
             |> Ash.Changeset.for_update(:update, %{intimacy: new_intimacy})
             |> Ash.update() do
          {:ok, _} ->
            Logger.info(
              "Decayed intimacy for user #{member.user_id} in guild #{member.guild_id} from #{member.intimacy} to #{new_intimacy}"
            )

            count + 1

          {:error, reason} ->
            Logger.error(
              "Failed to decay intimacy for user #{member.user_id} in guild #{member.guild_id}: #{inspect(reason)}"
            )

            count
        end
      else
        count
      end
    end)
  end
end
