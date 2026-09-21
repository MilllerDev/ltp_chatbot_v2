defmodule LtpChatbotWeb.HealthController do
  use Phoenix.Controller, formats: [:json]

  def show(conn, _params) do
    json(conn, %{status: "ok", service: "ltp_chatbot_web", inference: "not_configured"})
  end
end
