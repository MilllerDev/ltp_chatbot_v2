defmodule LtpChatbot.Sessions.SessionSupervisor do
  @moduledoc """
  Dynamic supervisor for the in-memory process associated with each session.
  """

  use DynamicSupervisor

  alias LtpChatbot.Sessions.SessionServer

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def start_session(session_id) do
    child_spec = {SessionServer, session_id}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @impl true
  def init(_arg), do: DynamicSupervisor.init(strategy: :one_for_one)
end
