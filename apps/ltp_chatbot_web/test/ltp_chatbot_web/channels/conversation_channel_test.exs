defmodule LtpChatbotWeb.ConversationChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  @endpoint LtpChatbotWeb.Endpoint

  setup do
    {:ok, _, socket} =
      Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
      |> Phoenix.ChannelTest.subscribe_and_join(LtpChatbotWeb.ConversationChannel, "conversation:session_abc123")

    %{socket: socket}
  end

  test "envío de mensaje devuelve confirmación y emite reply en vivo", %{socket: socket} do
    ref = push(socket, "message", %{"message" => "Hola mundo desde test", "client_msg_id" => "cid_999"})

    assert_reply ref, :ok, %{status: "delivered", client_msg_id: "cid_999"}
    assert_push "reply", %{text: reply_text, client_msg_id: "cid_999"}
    assert reply_text =~ "Hola mundo desde test"
    assert reply_text =~ "Phoenix"
  end

  test "rechaza mensajes no binarios con error de validación", %{socket: socket} do
    ref = push(socket, "message", %{"message" => 12345})
    assert_reply ref, :error, %{reason: "message must be a string"}
  end
end
