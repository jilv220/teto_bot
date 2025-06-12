defmodule TetoBot.Web.Router do
  @moduledoc """
  Main router interface for TetoBot using Plug and Cowboy.
  """

  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> send_resp(200, "Teto Bot Api is up")
  end

  post "/webhook" do
    conn
    |> TopggEx.Webhook.handle_webhook(get_topgg_web_auth_token(), fn payload ->
      case payload do
        %{"user" => user_id, "type" => "upvote", "bot" => bot_id} ->
          Logger.info("User #{user_id} voted for bot #{bot_id}!")

          case TetoBot.RateLimiting.record_vote(String.to_integer(user_id)) do
            :ok ->
              Logger.info("Successfully recorded vote for user #{user_id}")

            {:error, reason} ->
              Logger.error("Failed to record vote for user #{user_id}: #{inspect(reason)}")
          end

        %{"user" => user_id, "type" => "test"} ->
          Logger.info("Test webhook from user: #{user_id}")

          ## TODO: Handle weekend bonus for Topgg Voting
      end
    end)
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

  defp get_topgg_web_auth_token do
    Application.get_env(:teto_bot, :topgg_web_auth_token)
  end
end
