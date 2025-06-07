defmodule TetoBot.Interactions.Responses do
  @moduledoc """
  Handles creating and formatting Discord interaction responses.
  """

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias TetoBot.Constants

  @type response_options :: [ephemeral: boolean()]

  @spec success(Interaction.t(), String.t(), response_options()) :: :ok | Api.error()
  @doc """
  Creates a successful interaction response.
  """
  def success(interaction, content, opts \\ []) do
    create_response(interaction, content, opts)
  end

  @spec error(Interaction.t(), String.t(), response_options()) :: :ok | Api.error()
  @doc """
  Creates an error interaction response, defaulting to ephemeral.
  """
  def error(interaction, content, opts \\ []) do
    opts = Keyword.put_new(opts, :ephemeral, true)
    create_response(interaction, content, opts)
  end

  @spec permission_denied(Interaction.t(), String.t()) :: :ok | Api.error()
  @doc """
  Creates a standardized permission denied response.
  """
  def permission_denied(interaction, required_permission \\ "Manage Channels") do
    error(
      interaction,
      "You do not have permission to use this command. Only users with #{required_permission} permission can use this command."
    )
  end

  @spec whitelist_only(Interaction.t()) :: :ok | Api.error()
  @doc """
  Creates a standardized whitelist-only channel response.
  """
  def whitelist_only(interaction) do
    error(interaction, "This command can only be used in whitelisted channels.")
  end

  @spec create_response(Interaction.t(), String.t(), response_options()) :: :ok | Api.error()
  @doc """
  Creates a response for a Discord interaction.
  """
  def create_response(interaction, content, opts \\ []) do
    ephemeral = Keyword.get(opts, :ephemeral, false)
    flags = if ephemeral, do: Constants.ephemeral_flag(), else: nil

    response = %{
      type: Constants.interaction_response_type(),
      data: %{
        content: content,
        flags: flags
      }
    }

    Api.Interaction.create_response(interaction, response)
  end
end
