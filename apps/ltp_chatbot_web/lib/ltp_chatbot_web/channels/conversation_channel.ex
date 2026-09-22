defmodule LtpChatbotWeb.ConversationChannel do
  use Phoenix.Channel

  alias LtpChatbotWeb.ConversationService

  @impl true
  def join("conversation:" <> conversation_id, payload, socket) do
    with {:ok, session_id} <- ConversationService.ensure_session(conversation_id, "websocket"),
         {:ok, messages} <- ConversationService.resume(session_id, last_seq(payload)) do
      response = %{
        status: "connected",
        session_id: session_id,
        messages: messages,
        last_seq: max(last_seq(payload), last_message_seq(messages))
      }

      {:ok, response, assign(socket, :session_id, session_id)}
    else
      {:error, _reason} -> {:error, %{reason: "session_unavailable"}}
    end
  end

  @impl true
  def handle_in("message", %{"message" => message} = payload, socket) when is_binary(message) do
    with {:ok, client_msg_id} <- client_msg_id(payload),
         true <- valid_message?(message),
         session_id when is_binary(session_id) <- socket.assigns[:session_id],
         {:ok, result} <- ConversationService.handle_message(session_id, client_msg_id, message) do
      reply_payload =
        Map.put(
          result,
          :text,
          get_in(result, [:outbound, :body, "text"]) || get_in(result, [:outbound, :body, :text])
        )

      if result.status == "delivered" do
        push(socket, "reply", reply_payload)
      end

      {:reply,
       {:ok,
        %{
          status: result.status,
          client_msg_id: client_msg_id,
          inbound_seq: result.inbound.seq,
          outbound_seq: get_in(result, [:outbound, :seq])
        }}, socket}
    else
      false ->
        {:reply, {:error, %{reason: "message must be non-empty and at most 4000 bytes"}}, socket}

      {:error, :invalid_client_msg_id} ->
        {:reply, {:error, %{reason: "invalid client_msg_id"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "message could not be persisted"}}, socket}

      _ ->
        {:reply, {:error, %{reason: "session unavailable"}}, socket}
    end
  end

  def handle_in("message", _payload, socket) do
    {:reply, {:error, %{reason: "message must be a string"}}, socket}
  end

  defp client_msg_id(%{"client_msg_id" => nil}), do: {:ok, Ecto.UUID.generate()}

  defp client_msg_id(%{"client_msg_id" => client_msg_id}) do
    case Ecto.UUID.cast(client_msg_id) do
      {:ok, normalized_id} -> {:ok, normalized_id}
      :error -> {:error, :invalid_client_msg_id}
    end
  end

  defp client_msg_id(_payload), do: {:ok, Ecto.UUID.generate()}

  defp valid_message?(message) do
    trimmed = String.trim(message)
    trimmed != "" and byte_size(message) <= 4_000
  end

  defp last_seq(%{"last_seq" => last_seq}) when is_integer(last_seq) and last_seq >= 0, do: last_seq

  defp last_seq(%{"last_seq" => last_seq}) when is_binary(last_seq) do
    case Integer.parse(last_seq) do
      {value, ""} when value >= 0 -> value
      _ -> 0
    end
  end

  defp last_seq(_payload), do: 0

  defp last_message_seq([]), do: 0
  defp last_message_seq(messages), do: Enum.max_by(messages, & &1.seq).seq
end
