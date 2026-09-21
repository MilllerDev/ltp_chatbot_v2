defmodule LtpChatbot.Repo do
  use Ecto.Repo,
    otp_app: :ltp_chatbot,
    adapter: Ecto.Adapters.Postgres
end
