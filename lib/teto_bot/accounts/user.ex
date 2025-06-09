defmodule TetoBot.Accounts.User do
  @moduledoc """
  Represents a Discord user within the bot's system.
  """

  require Logger
  require Ash.Query
  require Nostrum.Snowflake

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

    action :create_user, :struct do
      argument :user_id, :integer, allow_nil?: false

      run fn input, _ ->
        user_id = input.arguments.user_id

        case Snowflake.is_snowflake(user_id) do
          false ->
            {:error, :invalid_id}

          true ->
            case __MODULE__
                 |> Ash.Changeset.for_create(:create, %{user_id: user_id})
                 |> Ash.create() do
              {:ok, user} ->
                {:ok, user}

              {:error, _changeset} = error ->
                error
            end
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

  identities do
    identity :unique_user_id, [:user_id]
  end
end
