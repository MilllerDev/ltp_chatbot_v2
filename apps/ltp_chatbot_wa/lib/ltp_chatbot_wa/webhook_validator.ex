defmodule LtpChatbotWA.WebhookValidator do
  @moduledoc """
  Valida la firma de seguridad X-Hub-Signature-256 de los webhooks de Meta.
  Utiliza comparación en tiempo constante para evitar ataques de temporización (timing attacks).
  """

  @doc """
  Verifica si el raw_body coincide con la cabecera x-hub-signature-256 dada el app_secret.
  """
  @spec valid_signature?(binary(), list() | binary(), binary()) :: boolean()
  def valid_signature?(raw_body, ["sha256=" <> sig], app_secret) when is_binary(raw_body) do
    verify_hash(raw_body, sig, app_secret)
  end

  def valid_signature?(raw_body, "sha256=" <> sig, app_secret) when is_binary(raw_body) do
    verify_hash(raw_body, sig, app_secret)
  end

  def valid_signature?(_raw_body, _signature, _app_secret), do: false

  defp verify_hash(raw_body, sig, app_secret) do
    expected =
      :crypto.mac(:hmac, :sha256, app_secret, raw_body)
      |> Base.encode16(case: :lower)

    :crypto.hash_equals(expected, sig)
  end
end
