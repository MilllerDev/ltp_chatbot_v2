defmodule LtpChatbotWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ltp_chatbot_web

  socket "/socket", LtpChatbotWeb.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
  plug Plug.MethodOverride
  plug Plug.Head
  plug LtpChatbotWeb.Router
end
