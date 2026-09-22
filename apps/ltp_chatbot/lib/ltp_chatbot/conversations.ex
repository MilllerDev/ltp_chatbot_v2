defmodule LtpChatbot.Conversations do
  @moduledoc """
  Context boundary for conversations and messages.

  The web layer and session processes use this module instead of depending
  directly on schemas or Ecto queries.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias LtpChatbot.Repo
  alias LtpChatbot.Sessions.{Message, Session}

  @spec create_session(map() | keyword()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}
  def create_session(attrs) do
    %Session{}
    |> Session.create_changeset(Map.new(attrs))
    |> Repo.insert()
  end

  @spec get_session(Ecto.UUID.t()) :: Session.t() | nil
  def get_session(session_id), do: Repo.get(Session, session_id)

  @spec touch_session(Ecto.UUID.t()) :: :ok | {:error, term()}
  def touch_session(session_id) do
    case Repo.get(Session, session_id) do
      nil -> {:error, :not_found}
      session -> session |> Session.touch_changeset() |> Repo.update() |> result_to_ok()
    end
  end

  @spec load_session_state(Ecto.UUID.t(), pos_integer()) ::
          {:ok, %{session: Session.t(), messages: [Message.t()]}} | {:error, :not_found}
  def load_session_state(session_id, limit) do
    case get_session(session_id) do
      nil ->
        {:error, :not_found}

      session ->
        messages =
          Message
          |> where([m], m.session_id == ^session_id)
          |> order_by([m], desc: m.seq)
          |> limit(^limit)
          |> Repo.all()
          |> Enum.reverse()

        {:ok, %{session: session, messages: messages}}
    end
  end

  @spec append_message(Ecto.UUID.t(), :in | :out, map(), Ecto.UUID.t() | nil) ::
          {:ok, Message.t()} | {:error, term()}
  def append_message(session_id, direction, body, client_msg_id \\ nil) do
    Multi.new()
    |> Multi.run(:session, fn repo, _changes -> lock_session(repo, session_id) end)
    |> Multi.run(:existing, fn repo, _changes ->
      find_existing_message(repo, session_id, client_msg_id)
    end)
    |> Multi.run(:message, fn repo, %{session: session, existing: existing} ->
      case existing do
        %Message{} = message -> {:ok, message}
        nil -> insert_message(repo, session, direction, body, client_msg_id)
      end
    end)
    |> Multi.run(:session_update, fn repo, %{session: session, existing: existing, message: message} ->
      if existing do
        {:ok, session}
      else
        session
        |> Ecto.Changeset.change(last_seq: message.seq, last_seen_at: DateTime.utc_now())
        |> repo.update()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message}} -> {:ok, message}
      {:error, _operation, reason, _changes} -> {:error, reason}
    end
  end

  @spec messages_after(Ecto.UUID.t(), non_neg_integer()) :: {:ok, [Message.t()]} | {:error, term()}
  def messages_after(session_id, last_seq) do
    messages =
      Message
      |> where([m], m.session_id == ^session_id and m.seq > ^last_seq)
      |> order_by([m], asc: m.seq)
      |> Repo.all()

    {:ok, messages}
  end

  @spec health_check() :: :ok
  def health_check, do: :ok

  defp lock_session(repo, session_id) do
    case repo.one(from s in Session, where: s.id == ^session_id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp find_existing_message(_repo, _session_id, nil), do: {:ok, nil}

  defp find_existing_message(repo, session_id, client_msg_id) do
    {:ok,
     repo.one(
       from m in Message,
         where: m.session_id == ^session_id and m.client_msg_id == ^client_msg_id
     )}
  end

  defp insert_message(repo, session, direction, body, client_msg_id) do
    %Message{}
    |> Message.changeset(%{
      session_id: session.id,
      seq: session.last_seq + 1,
      direction: Atom.to_string(direction),
      client_msg_id: client_msg_id,
      body: body
    })
    |> repo.insert()
  end

  defp result_to_ok({:ok, _session}), do: :ok
  defp result_to_ok({:error, reason}), do: {:error, reason}
end
