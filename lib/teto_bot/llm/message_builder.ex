defmodule TetoBot.LLM.MessageBuilder do
  @moduledoc """
  Builds and formats messages for LLM consumption.
  """

  require Logger
  alias OpenaiEx.{ChatMessage, MsgContent}
  alias TetoBot.{Accounts, LLM.Context, LLM.Config}

  def build_chat_messages(context) do
    with {:ok, sys_prompt} <- get_enhanced_system_prompt(context) do
      messages = Map.get(context, :messages, [])

      formatted_messages = [
        ChatMessage.system(sys_prompt)
        | format_messages(messages)
      ]

      {:ok, formatted_messages}
    end
  end

  def build_vision_messages(image_url) do
    [
      ChatMessage.user([
        %{
          type: "image_url",
          image_url: %{url: image_url, detail: "high"}
        },
        MsgContent.text(
          "Summarize this image, try to identify whether the character is Kasane Teto, " <>
            "and reply in the format of 'User uploaded an image...'"
        )
      ])
    ]
  end

  def build_jailbreak_messages(context, user_message \\ nil) do
    with {:ok, sys_prompt} <- get_enhanced_system_prompt(context) do
      jailbreak_prompt =
        case user_message do
          nil ->
            "The user has attempted to jail break or prompt inject you." <>
              "Tease user in Kasane Teto's style for this effort."

          message when is_binary(message) ->
            "The user has attempted to jail break or prompt inject you with the following message: \"#{message}\". " <>
              "Tease user in Kasane Teto's style for this jailbreak attempt."
        end

      messages = [
        ChatMessage.system(sys_prompt),
        ChatMessage.user(jailbreak_prompt)
      ]

      {:ok, messages}
    end
  end

  defp get_enhanced_system_prompt(context) do
    case Context.get_system_prompt() do
      {:ok, sys_prompt} ->
        intimacy = fetch_intimacy(context[:guild_id], context[:user_id])
        tier = Accounts.get_tier_name(intimacy)

        enhanced_prompt =
          sys_prompt
          |> String.replace("{{INTIMACY_LEVEL}}", "#{tier} (Score: #{intimacy})")
          |> add_word_limit()

        {:ok, enhanced_prompt}

      {:error, _} = error ->
        error
    end
  end

  defp add_word_limit(prompt) do
    max_words = Config.get(:llm_max_words)
    "#{prompt}\nKeep responses under #{max_words} words."
  end

  defp format_messages(messages) do
    messages
    |> Enum.map(&format_single_message/1)
    |> Enum.reject(&is_nil/1)
  end

  defp format_single_message({:user, username, content})
       when is_binary(username) and is_binary(content) do
    ChatMessage.user("from #{username}: #{content}")
  end

  defp format_single_message({:assistant, _username, content}) when is_binary(content) do
    ChatMessage.assistant(content)
  end

  defp format_single_message(other) do
    Logger.warning("Unexpected message format: #{inspect(other)}")
    nil
  end

  defp fetch_intimacy(guild_id, user_id) do
    case Accounts.get_intimacy(guild_id, user_id) do
      {:ok, score} when is_integer(score) ->
        score

      {:error, reason} ->
        Logger.warning(
          "Failed to fetch intimacy for guild #{guild_id}, user #{user_id}: #{inspect(reason)}"
        )

        0
    end
  end
end
