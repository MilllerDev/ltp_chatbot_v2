defmodule LtpChatbotWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: LtpChatbotWeb.PubSub},
      LtpChatbotWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: LtpChatbotWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LtpChatbotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
