defmodule TetoBot.Guilds.Guild do
  @moduledoc """
  Represents a guild (server) where the bot is installed.
  """

  require Nostrum.Snowflake
  require Logger
  require Ash.Query

  alias TetoBot.Guilds.Cache
  alias TetoBot.Accounts.UserGuild
  alias TetoBot.Repo
  alias Nostrum.Snowflake

  import Ecto.Query

  use Ash.Resource,
    domain: TetoBot.Guilds,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "guilds"
    repo TetoBot.Repo
  end

  actions do
    # Add default CRUD actions
    defaults [:read, :destroy, create: :*, update: :*]

    action :guild_ids, {:array, :integer} do
      run fn _, _ ->
        __MODULE__
        |> Ash.Query.for_read(:read)
        |> Ash.Query.select([:guild_id])
        |> Ash.read!()
        |> Enum.map(& &1.guild_id)
        |> then(&{:ok, &1})
      end
    end

    action :create_guild, :struct do
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id

        case Snowflake.is_snowflake(guild_id) do
          false ->
            {:error, :invalid_id}

          true ->
            case __MODULE__
                 |> Ash.Changeset.for_create(:create, %{guild_id: guild_id})
                 |> Ash.create() do
              {:ok, guild} ->
                Cache.add(guild_id)
                {:ok, guild}

              {:error, _changeset} = error ->
                error
            end
        end
      end
    end

    action :delete_guild, :struct do
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id

        case Snowflake.is_snowflake(guild_id) do
          false ->
            {:error, :invalid_id}

          true ->
            case __MODULE__
                 |> Ash.Query.for_read(:read)
                 |> Ash.Query.filter(guild_id == ^guild_id)
                 |> Ash.read_one() do
              {:ok, nil} ->
                {:error, :not_found}

              {:ok, guild} ->
                case Ash.destroy(guild) do
                  :ok ->
                    Cache.remove(guild_id)
                    {:ok, guild}

                  {:error, _changeset} = error ->
                    error
                end

              {:error, reason} ->
                {:error, reason}
            end
        end
      end
    end

    action :member_check, :boolean do
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id

        case Snowflake.is_snowflake(guild_id) do
          false ->
            {:ok, false}

          true ->
            # Fast cache lookup first
            if Cache.exists?(guild_id) do
              {:ok, true}
            else
              # Fallback to database lookup
              case __MODULE__
                   |> Ash.Query.for_read(:read)
                   |> Ash.Query.filter(guild_id == ^guild_id)
                   |> Ash.read_one() do
                {:ok, nil} ->
                  {:ok, false}

                {:ok, _guild} ->
                  # Add to cache for future fast lookups
                  Cache.add(guild_id)
                  {:ok, true}

                {:error, _reason} ->
                  {:ok, false}
              end
            end
        end
      end
    end

    action :members, {:array, :struct} do
      argument :guild_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id

        case Snowflake.is_snowflake(guild_id) do
          false ->
            {:error, :invalid_id}

          true ->
            try do
              result =
                from(ug in UserGuild,
                  where: ug.guild_id == ^guild_id
                )
                |> Repo.all()

              {:ok, result}
            rescue
              error in Ecto.QueryError ->
                Logger.error("Failed to get members: #{inspect(error)}")
                {:error, error}
            end
        end
      end
    end

    action :warm_cache do
      run fn _, _ ->
        __MODULE__
        |> Ash.Query.for_read(:read)
        |> Ash.read!()
        |> case do
          [] ->
            :ok

          guilds ->
            Enum.each(guilds, &Cache.add(&1.guild_id))
        end
      end
    end

    action :cache_stats, :map do
      run fn _, _ ->
        {:ok,
         %{
           cached_guilds: Cache.count(),
           cached_guild_ids: Cache.list()
         }}
      end
    end
  end

  attributes do
    # Add an auto-incrementing integer primary key
    uuid_primary_key :id

    # The Discord Guild ID
    attribute :guild_id, :integer, allow_nil?: false, public?: true

    # Adapt Default Ecto
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_guild_id, [:guild_id]
  end
end
