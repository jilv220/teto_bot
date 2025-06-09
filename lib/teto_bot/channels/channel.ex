defmodule TetoBot.Channels.Channel do
  @moduledoc """
  Represents a channel that is whitelisted for bot operation.
  """

  require Nostrum.Snowflake
  require Logger
  require Ash.Query

  alias TetoBot.Channels.Cache
  alias Nostrum.Snowflake

  use Ash.Resource,
    domain: TetoBot.Channels,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "channels"
    repo TetoBot.Repo
  end

  actions do
    # Add default CRUD actions
    defaults [:read, :destroy, create: :*, update: :*]

    action :whitelist_channel, :struct do
      argument :guild_id, :integer, allow_nil?: false
      argument :channel_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id
        channel_id = input.arguments.channel_id

        case Snowflake.is_snowflake(guild_id) and Snowflake.is_snowflake(channel_id) do
          false ->
            {:error, :invalid_id}

          true ->
            case __MODULE__
                 |> Ash.Changeset.for_create(:create, %{
                   guild_id: guild_id,
                   channel_id: channel_id
                 })
                 |> Ash.create() do
              {:ok, channel} ->
                Cache.add(channel_id)
                {:ok, channel}

              {:error, _changeset} = error ->
                error
            end
        end
      end
    end

    action :blacklist_channel, :struct do
      argument :guild_id, :integer, allow_nil?: false
      argument :channel_id, :integer, allow_nil?: false

      run fn input, _ ->
        guild_id = input.arguments.guild_id
        channel_id = input.arguments.channel_id

        case Snowflake.is_snowflake(guild_id) and Snowflake.is_snowflake(channel_id) do
          false ->
            {:error, :invalid_id}

          true ->
            case __MODULE__
                 |> Ash.Query.for_read(:read)
                 |> Ash.Query.filter(guild_id == ^guild_id and channel_id == ^channel_id)
                 |> Ash.read_one(not_found_error?: true) do
              {:ok, channel} ->
                case Ash.destroy(channel) do
                  :ok ->
                    Cache.remove(channel_id)
                    {:ok, channel}

                  error ->
                    error
                end

              {:error, reason} ->
                {:error, reason}
            end
        end
      end
    end

    action :whitelisted_check, :boolean do
      argument :channel_id, :integer, allow_nil?: false

      run fn input, _ ->
        channel_id = input.arguments.channel_id

        case Snowflake.is_snowflake(channel_id) do
          false ->
            {:ok, false}

          true ->
            # Fast cache lookup first
            if Cache.exists?(channel_id) do
              {:ok, true}
            else
              # Fallback to database lookup
              case __MODULE__
                   |> Ash.Query.for_read(:read)
                   |> Ash.Query.filter(channel_id == ^channel_id)
                   |> Ash.read_one() do
                {:ok, nil} ->
                  {:ok, false}

                {:ok, _channel} ->
                  # Add to cache for future fast lookups
                  Cache.add(channel_id)
                  {:ok, true}

                {:error, _reason} ->
                  {:ok, false}
              end
            end
        end
      end
    end

    action :cache_stats, :map do
      run fn _, _ ->
        {:ok,
         %{
           cached_channels: Cache.count(),
           cached_channel_ids: Cache.list()
         }}
      end
    end
  end

  attributes do
    # Add an auto-incrementing integer primary key
    uuid_primary_key :id

    # The Discord Channel ID
    attribute :channel_id, :integer, allow_nil?: false, public?: true

    # The Discord Guild ID
    attribute :guild_id, :integer, allow_nil?: false, public?: true

    # Adapt Default Ecto timestamps
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :guild, TetoBot.Guilds.Guild do
      source_attribute :guild_id
      destination_attribute :guild_id
    end
  end

  identities do
    identity :unique_channel_id, [:channel_id]
  end
end
