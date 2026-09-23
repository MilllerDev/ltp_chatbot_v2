defmodule LtpChatbotWeb.SessionToken do
  @moduledoc """
  Generates and verifies cryptographic session tokens using Phoenix.Token.

  Provides stateless authentication for WebSocket connections to prevent
  unauthorized eavesdropping or spoofing of sessions.
  """

  @salt "session_auth"
  @default_max_age 86_400

  @doc """
  Signs a session token containing the session_id and user tier.
  """
  @spec sign(Ecto.UUID.t(), String.t()) :: String.t()
  def sign(session_id, tier \\ "anon") when is_binary(session_id) and is_binary(tier) do
    Phoenix.Token.sign(LtpChatbotWeb.Endpoint, @salt, %{
      session_id: session_id,
      tier: tier
    })
  end

  @doc """
  Verifies a session token, returning the payload if valid and within TTL.
  """
  @spec verify(String.t(), non_neg_integer()) ::
          {:ok, %{session_id: Ecto.UUID.t(), tier: String.t()}} | {:error, :invalid | :expired}
  def verify(token, max_age \\ @default_max_age)

  def verify(token, max_age) when is_binary(token) and is_integer(max_age) do
    case Phoenix.Token.verify(LtpChatbotWeb.Endpoint, @salt, token, max_age: max_age) do
      {:ok, %{session_id: session_id, tier: tier}} = result
      when is_binary(session_id) and is_binary(tier) ->
        result

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid}
    end
  end

  def verify(_token, _max_age), do: {:error, :invalid}
end
