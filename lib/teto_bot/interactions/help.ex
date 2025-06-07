defmodule TetoBot.Interactions.Help do
  @moduledoc """
  Handles the /help Discord slash command.
  """

  alias Nostrum.Struct.Interaction
  alias TetoBot.Commands
  alias TetoBot.Interactions.Responses

  @spec handle_help(Interaction.t()) :: :ok | Nostrum.Api.error()
  @doc """
  Handles the /help command - displays information about the bot and its commands.
  """
  def handle_help(interaction) do
    help_message = build_help_message()
    Responses.success(interaction, help_message, ephemeral: true)
  end

  @spec build_help_message() :: String.t()
  defp build_help_message do
    """
    **TetoBot Help**

    TetoBot cosplays as Kasane Teto, responding to messages in whitelisted channels with AI-generated replies.

    **Commands:**
    #{Enum.map_join(Commands.commands(), "\n", fn cmd ->
      options = if Map.has_key?(cmd, :options), do: " " <> Enum.map_join(cmd.options, " ", &"<#{&1.name}>"), else: ""
      "- `/#{cmd.name}#{options}`: #{cmd.description}"
    end)}

    **Support:**
    For issues or feedback, please create an issue in our [Github Repo](https://github.com/jilv220/teto_bot/issues)
    """
  end
end
