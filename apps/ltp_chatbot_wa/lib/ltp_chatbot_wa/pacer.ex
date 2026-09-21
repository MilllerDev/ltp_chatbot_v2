defmodule LtpChatbotWA.Pacer do
  @moduledoc """
  Rate limiter GCRA lock-free con enteros atómicos (`:atomics`).

  Estado: Un entero atómico de 64 bits con el TAT (Theoretical Arrival Time)
  del próximo evento permitido, medido en nanosegundos monotónicos.
  `take/2` es O(1), no asigna memoria en el heap y no involucra al scheduler.
  """

  # Ráfaga tolerada: 100 ms de crédito acumulable.
  @burst_ns 100_000_000

  @doc "Inicializa una referencia atómica para el pacer."
  def new, do: :atomics.new(1, signed: true)

  @doc """
  Devuelve :ok si se puede proceder inmediatamente,
  o {:wait, microsegundos} hasta el próximo slot permitido.
  """
  def take(ref, rate_per_s) when rate_per_s > 0 do
    interval_ns = div(1_000_000_000, rate_per_s)
    take(ref, interval_ns, System.monotonic_time(:nanosecond), 0)
  end

  defp take(_ref, interval_ns, _now, tries) when tries > 64 do
    {:wait, div(interval_ns, 1_000)}
  end

  defp take(ref, interval_ns, now, tries) do
    prev = :atomics.get(ref, 1)
    base = max(prev, now - @burst_ns)
    tat = base + interval_ns

    cond do
      tat - now > @burst_ns ->
        {:wait, div(tat - now, 1_000)}

      :atomics.compare_exchange(ref, 1, prev, tat) == :ok ->
        :ok

      true ->
        take(ref, interval_ns, System.monotonic_time(:nanosecond), tries + 1)
    end
  end
end
