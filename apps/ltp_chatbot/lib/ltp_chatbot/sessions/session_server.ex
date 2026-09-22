defmodule LtpChatbot.Sessions.SessionServer do
  @moduledoc """
  Hot, rebuildable state for one conversational session.

  This process deliberately has no transport dependency. Sockets and other
  transports can consume the returned events in a later phase.
  """

  use GenServer

  alias LtpChatbot.Conversations

  @ring_size 200
  @idle_timeout :timer.minutes(30)

  @type state :: %{
          id: Ecto.UUID.t(),
          last_seq: non_neg_integer(),
          ring: [map()],
          seen_client_msg_ids: MapSet.t(Ecto.UUID.t())
        }

  def child_spec(session_id) do
    %{
      id: {__MODULE__, session_id},
      start: {__MODULE__, :start_link, [session_id]},
      restart: :transient,
      type: :worker
    }
  end

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: via(session_id))
  end

  def via(session_id), do: {:via, Registry, {LtpChatbot.Sessions.Registry, session_id}}

  def inbound(session_id, client_msg_id, body) do
    with {:ok, pid} <- ensure_started(session_id) do
      GenServer.call(pid, {:inbound, client_msg_id, body}, 5_000)
    end
  end

  def append_outbound(session_id, body) do
    with {:ok, pid} <- ensure_started(session_id) do
      GenServer.call(pid, {:outbound, body}, 5_000)
    end
  end

  def resume(session_id, last_seq) when is_integer(last_seq) and last_seq >= 0 do
    with {:ok, pid} <- ensure_started(session_id) do
      GenServer.call(pid, {:resume, last_seq}, 5_000)
    end
  end

  def touch(session_id) do
    with {:ok, pid} <- ensure_started(session_id) do
      GenServer.call(pid, :touch, 5_000)
    end
  end

  @impl true
  def init(session_id) do
    case Conversations.load_session_state(session_id, @ring_size) do
      {:ok, %{session: session, messages: messages}} ->
        state = %{
          id: session.id,
          last_seq: session.last_seq,
          ring: Enum.map(messages, &message_event/1),
          seen_client_msg_ids: client_msg_ids(messages)
        }

        {:ok, state, @idle_timeout}

      {:error, :not_found} ->
        {:stop, :normal}
    end
  end

  @impl true
  def handle_call({:inbound, client_msg_id, body}, _from, state) do
    if MapSet.member?(state.seen_client_msg_ids, client_msg_id) do
      {:reply, {:ok, :duplicate}, state, @idle_timeout}
    else
      case Conversations.append_message(state.id, :in, body, client_msg_id) do
        {:ok, message} ->
          {:reply, {:ok, message}, remember(state, message), @idle_timeout}

        {:error, reason} ->
          {:reply, {:error, reason}, state, @idle_timeout}
      end
    end
  end

  @impl true
  def handle_call({:outbound, body}, _from, state) do
    case Conversations.append_message(state.id, :out, body) do
      {:ok, message} ->
        {:reply, {:ok, message}, remember(state, message), @idle_timeout}

      {:error, reason} ->
        {:reply, {:error, reason}, state, @idle_timeout}
    end
  end

  @impl true
  def handle_call({:resume, last_seq}, _from, state) do
    messages =
      case Enum.filter(state.ring, &(&1.seq > last_seq)) do
        [] when last_seq < state.last_seq - @ring_size ->
          case Conversations.messages_after(state.id, last_seq) do
            {:ok, messages} -> {:ok, Enum.map(messages, &message_event/1)}
            error -> error
          end

        local ->
          {:ok, local}
      end

    {:reply, messages, state, @idle_timeout}
  end

  @impl true
  def handle_call(:touch, _from, state) do
    {:reply, Conversations.touch_session(state.id), state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state), do: {:stop, :normal, state}

  defp ensure_started(session_id) do
    case Registry.lookup(LtpChatbot.Sessions.Registry, session_id) do
      [{pid, _value}] -> {:ok, pid}
      [] -> LtpChatbot.Sessions.SessionSupervisor.start_session(session_id)
    end
  end

  defp remember(state, message) do
    %{
      state
      | last_seq: message.seq,
        ring: Enum.take([message_event(message) | state.ring], @ring_size),
        seen_client_msg_ids:
          if(message.client_msg_id,
            do: MapSet.put(state.seen_client_msg_ids, message.client_msg_id),
            else: state.seen_client_msg_ids
          )
    }
  end

  defp message_event(message) do
    %{
      seq: message.seq,
      direction: message.direction,
      client_msg_id: message.client_msg_id,
      body: message.body,
      inserted_at: message.inserted_at
    }
  end

  defp client_msg_ids(messages) do
    messages
    |> Enum.map(& &1.client_msg_id)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end
end
