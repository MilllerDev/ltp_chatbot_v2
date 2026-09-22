defmodule LtpChatbot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LtpChatbot.Repo,
      {Registry, keys: :unique, name: LtpChatbot.Sessions.Registry},
      {LtpChatbot.Sessions.SessionSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: LtpChatbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
