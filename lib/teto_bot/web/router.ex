defmodule TetoBot.Web.Router do
  @moduledoc """
  Main router interface for TetoBot using Plug and Cowboy.
  """

  use Plug.Router
  require Logger

  @topgg_web_auth_token Application.compile_env(:teto_bot, :topgg_web_auth_token)

  plug(Plug.Logger)

  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> send_resp(200, "Teto Bot Api is up")
  end

  post "/webhook" do
    conn
    |> TopggEx.Webhook.verify_and_parse(@topgg_web_auth_token)
    |> case do
      {:ok, %{"user" => user_id, "type" => "upvote", "isWeekend" => true}} ->
        Logger.info("Received vote from #{user_id}")
        send_resp(conn, 200, "")

      {:ok, %{"user" => user_id, "type" => "upvote", "isWeekend" => false}} ->
        Logger.info("Received a test vote from #{user_id}")
        send_resp(conn, 200, "")

      {:ok, %{"user" => user_id, "type" => "test"}} ->
        Logger.info("Received a test vote from #{user_id}")
        send_resp(conn, 200, "")

      {:error, :invalid_payload_format} ->
        conn
        |> send_resp(400, "Invalid payload format")

      {:error, {:missing_fields, fields}} ->
        conn
        |> send_resp(400, "Missing required fields: #{Enum.join(fields, ", ")}")

      {:error, {:invalid_field_type, field}} ->
        conn
        |> send_resp(400, "Invalid type for field: #{field}")

      {:error, :unauthorized} ->
        send_resp(conn, 403, Jason.encode!(%{error: "Unauthorized"}))

      {:error, :invalid_body} ->
        send_resp(conn, 400, Jason.encode!(%{error: "Invalid body"}))

      {:error, :malformed_request} ->
        send_resp(conn, 422, Jason.encode!(%{error: "Malformed request"}))
    end
  end

  # Catch-all for unmatched routes
  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  @spec send_json_response(Plug.Conn.t(), integer(), map()) :: Plug.Conn.t()
  defp send_json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
