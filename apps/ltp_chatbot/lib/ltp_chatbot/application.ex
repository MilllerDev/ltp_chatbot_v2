defmodule LtpChatbot.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [LtpChatbot.Repo]
    opts = [strategy: :one_for_one, name: LtpChatbot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
