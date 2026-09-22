defmodule LtpChatbotWeb.ConversationChannel do
  use Phoenix.Channel

  @impl true
  def join("conversation:" <> conversation_id, _payload, socket) do
    {:ok, %{status: "connected", session_id: conversation_id}, assign(socket, :session_id, conversation_id)}
  end

  @impl true
  def handle_in("message", %{"message" => message} = payload, socket) when is_binary(message) do
    client_msg_id = Map.get(payload, "client_msg_id") || Ecto.UUID.generate()
    session_id = socket.assigns[:session_id] || "default"

    # Eco interactivo en tiempo real a través del WebSocket
    push(socket, "reply", %{
      text: "¡Hola! He recibido tu mensaje: \"#{message}\". El servidor Phoenix está respondiendo en vivo.",
      client_msg_id: client_msg_id,
      session_id: session_id,
      timestamp: System.system_time(:millisecond)
    })

    {:reply, {:ok, %{status: "delivered", client_msg_id: client_msg_id}}, socket}
  end

  def handle_in("message", _payload, socket) do
    {:reply, {:error, %{reason: "message must be a string"}}, socket}
  end
end
