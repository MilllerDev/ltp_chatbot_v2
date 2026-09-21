defmodule LtpChatbotWeb.ConversationController do
  use Phoenix.Controller, formats: [:json]

  def create(conn, %{"message" => message}) when is_binary(message) and byte_size(message) > 0 do
    json(conn, %{status: "accepted", message: message, inference: "not_configured"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "message must be a non-empty string"})
  end
end
