defmodule LtpChatbotWeb.ConversationChannel do
  use Phoenix.Channel

  @impl true
  def join("conversation:" <> _conversation_id, _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("message", %{"message" => message}, socket) when is_binary(message) do
    {:reply, {:ok, %{status: "accepted", inference: "not_configured"}}, socket}
  end

  def handle_in("message", _payload, socket) do
    {:reply, {:error, %{reason: "message must be a string"}}, socket}
  end
end
