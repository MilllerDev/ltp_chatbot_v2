defmodule LtpChatbotWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html", "javascript"]
    plug :fetch_query_params
  end

  scope "/", LtpChatbotWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/conversations", ConversationController, :create
  end

  scope "/", LtpChatbotWeb do
    pipe_through :browser

    get "/widget", WidgetController, :index
    get "/widget/embed.js", WidgetController, :embed_js
  end
end
