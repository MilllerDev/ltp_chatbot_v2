defmodule LtpChatbotWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LtpChatbotWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/conversations", ConversationController, :create
  end
end
