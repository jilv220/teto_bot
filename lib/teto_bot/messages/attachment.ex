defmodule TetoBot.Messages.Attachment do
  @moduledoc """
  Module for handling attachment messages, including image processing and cache updates.
  """

  require Logger
  alias Nostrum.Cache.MessageCache
  alias Nostrum.Struct
  alias TetoBot.LLM

  def image?(filename) do
    MIME.from_path(filename) in [
      "image/jpeg",
      "image/jpg",
      "image/png",
      "image/gif",
      "image/webp",
      "image/x-icon"
    ]
  end

  def audio?(filename) do
    MIME.from_path(filename) in [
      "audio/mpeg",
      "audio/mp3",
      "audio/ogg",
      "audio/wav",
      "audio/webm"
    ]
  end

  @doc """
  Processes image attachments and updates message cache if necessary.
  Returns the original message if no attachments or after processing.
  """
  @spec process_attachments(Nostrum.Struct.Message.t()) :: Nostrum.Struct.Message.t()
  def process_attachments(%Struct.Message{attachments: attachments} = msg) do
    attachments = attachments || []

    case attachments do
      [] ->
        msg

      [%Struct.Message.Attachment{url: url, filename: filename} | _] ->
        cond do
          image?(filename) ->
            handle_image_attachment(msg, url)

          audio?(filename) ->
            handle_audio_attachment(filename)

          true ->
            handle_unsupported_attachment(filename)
        end
    end
  end

  @doc """
  Handles processing of a single image attachment by summarizing it with LLM.
  """
  @spec handle_image_attachment(Nostrum.Struct.Message.t(), String.t()) ::
          Nostrum.Struct.Message.t()
  def handle_image_attachment(msg, url) do
    Logger.info("Processing image attachment: #{url}")
    openai = LLM.get_client()

    case LLM.summarize_image(openai, url) do
      {:ok, image_summary} ->
        Logger.debug("Image summary generated: #{inspect(image_summary)}")
        update_message_with_image_summary(msg, image_summary)

      {:error, reason} ->
        Logger.error("Failed to summarize image: #{inspect(reason)}")
        raise RuntimeError, message: "Failed to summarize image"
    end
  end

  def handle_audio_attachment(filename) do
    raise RuntimeError, message: "Audio attachment are not supported: #{filename}"
  end

  @doc """
  Updates message cache with image summary appended to content.
  """
  @spec update_message_with_image_summary(Nostrum.Struct.Message.t(), String.t()) ::
          Nostrum.Struct.Message.t()
  def update_message_with_image_summary(msg, image_summary) do
    update_payload = %{
      id: msg.id,
      content: msg.content <> " Image attachment: " <> image_summary
    }

    MessageCache.Mnesia.update(update_payload)
    msg
  end

  @doc """
  Handles unsupported attachment types by raising an error.
  """
  @spec handle_unsupported_attachment(String.t()) :: no_return()
  def handle_unsupported_attachment(filename) do
    raise RuntimeError, message: "Unsupported attachment type: #{filename}"
  end
end
