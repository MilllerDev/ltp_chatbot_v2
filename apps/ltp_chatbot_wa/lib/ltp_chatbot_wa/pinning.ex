defmodule LtpChatbotWA.Pinning do
  @moduledoc """
  Ancla un número de teléfono de WhatsApp a exactamente un nodo del clúster
  mediante PostgreSQL Advisory Locks (`pg_try_advisory_lock`).

  Esto garantiza que solo un nodo emita y controle la tasa del número,
  haciendo que el rate limiting sea puramente local y en memoria RAM.
  """

  alias LtpChatbot.Repo

  @doc """
  Intenta reclamar la exclusividad del número telefónico para este nodo.
  Devuelve `{:ok, :acquired}` si se obtuvo el candado, o `{:error, :locked_by_other}`.
  """
  @spec claim(String.t() | integer()) :: {:ok, :acquired} | {:error, :locked_by_other}
  def claim(phone_number_id) do
    lock_key = :erlang.phash2(phone_number_id, 2_147_483_647)

    case Repo.query("SELECT pg_try_advisory_lock($1)", [lock_key]) do
      {:ok, %{rows: [[true]]}} -> {:ok, :acquired}
      {:ok, %{rows: [[false]]}} -> {:error, :locked_by_other}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Libera el candado del número telefónico.
  """
  @spec release(String.t() | integer()) :: :ok | {:error, term()}
  def release(phone_number_id) do
    lock_key = :erlang.phash2(phone_number_id, 2_147_483_647)

    case Repo.query("SELECT pg_advisory_unlock($1)", [lock_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
