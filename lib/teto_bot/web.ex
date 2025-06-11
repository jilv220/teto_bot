defmodule TetoBot.Web do
  @moduledoc """
  Main HTTP interface for TetoBot using Plug and Cowboy.

  This module provides web endpoints for bot status, health checks,
  and potentially webhook integrations.
  """

  use Plug.Router
  require Logger

  @topgg_web_auth_token Application.compile_env(:teto_bot, :topgg_web_auth_token)

  plug(Plug.Logger)

  plug(TopggEx.Webhook,
    authorization: @topgg_web_auth_token,
    assign_key: :vote_data
  )

  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> send_resp(200, "Teto Bot Api is up")
  end

  post "/webhook" do
    case conn.assigns.vote_data do
      %{"user" => user_id} ->
        Logger.info("Received vote from #{user_id}")

        send_resp(conn, 204, "")

      _ ->
        send_resp(conn, 400, "Invalid vote data")
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
