defmodule LtpChatbotWA do
  @moduledoc """
  Línea de límite (Context boundary) para operaciones de WhatsApp.

  Encapsula la validación de webhooks, el rate limiting GCRA (Pacer),
  el anclaje de números a nodos por advisory locks y los pipelines Broadway.
  """

  alias LtpChatbotWA.{Pacer, Pinning, WebhookValidator}

  @doc """
  Valida la firma HMAC de un webhook de Meta en tiempo constante.
  """
  defdelegate valid_webhook_signature?(raw_body, signature, app_secret),
    to: WebhookValidator,
    as: :valid_signature?

  @doc """
  Intenta anclar un número de WhatsApp al nodo actual.
  """
  defdelegate claim_phone_number(phone_number_id),
    to: Pinning,
    as: :claim

  @doc """
  Crea un nuevo Pacer GCRA lock-free con enteros atómicos.
  """
  defdelegate new_pacer, to: Pacer, as: :new

  @doc """
  Solicita un slot al Pacer para enviar a una tasa determinada.
  """
  defdelegate take_pacer_slot(ref, rate_per_s), to: Pacer, as: :take
end
