defmodule LtpChatbotWA.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Pool Finch HTTP/2 optimizado para llamadas a Meta Graph API
      {Finch, name: LtpChatbotWA.Finch},
      # Registro de pipelines emisores por cada phone_number_id anclado
      {Registry, keys: :unique, name: LtpChatbotWA.SenderRegistry},
      # Supervisor dinámico para lanzar pipelines de envío por número
      {DynamicSupervisor, strategy: :one_for_one, name: LtpChatbotWA.SenderSupervisor}
    ]

    opts = [strategy: :one_for_one, name: LtpChatbotWA.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
