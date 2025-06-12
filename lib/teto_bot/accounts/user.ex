defmodule TetoBot.Accounts.User do
  @moduledoc """
  Represents a Discord user within the bot's system.
  """

  require Logger
  require Ash.Query
  require Nostrum.Snowflake

  alias TetoBot.Accounts.User
  alias Nostrum.Snowflake

  use Ash.Resource,
    domain: TetoBot.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "users"
    repo TetoBot.Repo
  end

  actions do
    # Add default CRUD actions
    defaults [:read, :destroy, create: :*, update: :*]

    create :create_user do
      accept [:user_id]

      validate fn changeset, _ ->
        user_id = Ash.Changeset.get_attribute(changeset, :user_id)

        if Snowflake.is_snowflake(user_id) do
          :ok
        else
          {:error, field: :user_id, message: "must be a valid Discord snowflake"}
        end
      end
    end

    action :get_user, :struct do
      argument :user_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id

        case Snowflake.is_snowflake(user_id) do
          false ->
            {:error, :invalid_id}

          true ->
            __MODULE__
            |> Ash.Query.for_read(:read)
            |> Ash.Query.filter(user_id == ^user_id)
            |> Ash.read_one()
        end
      end
    end
  end

  attributes do
    # Use user_id as primary key (no auto-generated id) - database stores as bigint
    attribute :user_id, :integer, primary_key?: true, allow_nil?: false, public?: true
    attribute :role, User.Role, default: :user

    # Vote tracking for rate limiting
    attribute :last_voted_at, :utc_datetime, public?: true

    # Message credits for charging system
    attribute :message_credits, :integer, default: 10, allow_nil?: false, public?: true

    # Default Ecto timestamps
    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :user_guilds, TetoBot.Accounts.UserGuild do
      source_attribute :user_id
      destination_attribute :user_id
    end
  end

  calculations do
    calculate :is_voted_user,
              :boolean,
              expr(
                not is_nil(last_voted_at) and
                  last_voted_at >= fragment("date_trunc('day', NOW() AT TIME ZONE 'UTC')")
              )

    calculate :has_voted_today,
              :boolean,
              expr(
                not is_nil(last_voted_at) and
                  last_voted_at >= fragment("date_trunc('day', NOW() AT TIME ZONE 'UTC')")
              )
  end

  aggregates do
    sum :total_daily_messages, :user_guilds, :daily_message_count do
      default 0
    end
  end

  identities do
    identity :unique_user_id, [:user_id]
  end
end
