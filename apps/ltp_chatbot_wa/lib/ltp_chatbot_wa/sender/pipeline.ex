defmodule LtpChatbotWA.Sender.Pipeline do
  @moduledoc """
  Pipeline Broadway de emisión para un número de WhatsApp específico.

  Aísla el tráfico del número, aplica backpressure automático,
  gestiona peticiones HTTP/2 concurrentes y agrupa confirmaciones en lote a la base de datos.
  """

  use Broadway

  @doc """
  Inicia el pipeline para un phone_number_id con su tasa objetivo (MPS).
  """
  def start_link(opts) do
    phone_number_id = Keyword.fetch!(opts, :phone_number_id)
    mps = Keyword.get(opts, :mps, 80)

    Broadway.start_link(__MODULE__,
      name: via_tuple(phone_number_id),
      producer: [
        module: {Broadway.DummyProducer, []},
        concurrency: 1,
        rate_limiting: [allowed_messages: mps, interval: 1_000]
      ],
      processors: [
        default: [
          # ~32 peticiones en vuelo: mps * p99_latencia(0.4s)
          concurrency: max(8, ceil(mps * 0.4)),
          max_demand: 10
        ]
      ],
      batchers: [
        db: [concurrency: 2, batch_size: 200, batch_timeout: 250]
      ],
      context: opts
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    # Aquí se invoca el adapter de Cloud API / MM Lite vía Finch
    message
  end

  @impl true
  def handle_batch(:db, messages, _batch_info, _context) do
    # Persistencia de confirmaciones en lote (batch ACK)
    messages
  end

  def via_tuple(phone_number_id) do
    {:via, Registry, {LtpChatbotWA.SenderRegistry, phone_number_id}}
  end
end
