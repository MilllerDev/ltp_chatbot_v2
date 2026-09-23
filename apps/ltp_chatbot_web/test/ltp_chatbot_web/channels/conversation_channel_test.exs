defmodule LtpChatbotWeb.ConversationChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  @endpoint LtpChatbotWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(LtpChatbot.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(LtpChatbot.Repo, {:shared, self()})

    session_id = Ecto.UUID.generate()
    token = LtpChatbotWeb.SessionToken.sign(session_id, "anon")

    {:ok, _, socket} =
      Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
      |> Phoenix.ChannelTest.subscribe_and_join(
        LtpChatbotWeb.ConversationChannel,
        "conversation:#{session_id}",
        %{"token" => token}
      )

    %{socket: socket, session_id: session_id, token: token}
  end

  test "envío de mensaje devuelve confirmación y emite reply en vivo", %{socket: socket} do
    client_msg_id = Ecto.UUID.generate()

    ref =
      push(socket, "message", %{
        "message" => "Hola mundo desde test",
        "client_msg_id" => client_msg_id
      })

    assert_reply ref, :ok, %{
      status: "delivered",
      client_msg_id: ^client_msg_id,
      inbound_seq: 1,
      outbound_seq: 2
    }

    assert_push "reply", %{text: reply_text, outbound: %{seq: 2}}
    assert reply_text =~ "Hola mundo desde test"
    assert reply_text =~ "Phoenix"
  end

  test "rechaza mensajes no binarios con error de validación", %{socket: socket} do
    ref = push(socket, "message", %{"message" => 12345})
    assert_reply ref, :error, %{reason: "message must be a string"}
  end

  test "rechaza mensajes vacíos o con solo espacios", %{socket: socket} do
    ref = push(socket, "message", %{"message" => "   "})
    assert_reply ref, :error, %{reason: "message must be non-empty and at most 4000 bytes"}
  end

  test "rechaza client_msg_id con formato no UUID", %{socket: socket} do
    ref = push(socket, "message", %{"message" => "Hola", "client_msg_id" => "invalido"})
    assert_reply ref, :error, %{reason: "invalid client_msg_id"}
  end

  test "desduplica mensajes con el mismo client_msg_id", %{socket: socket} do
    client_msg_id = Ecto.UUID.generate()

    ref1 =
      push(socket, "message", %{
        "message" => "Mensaje único",
        "client_msg_id" => client_msg_id
      })

    assert_reply ref1, :ok, %{
      status: "delivered",
      client_msg_id: ^client_msg_id,
      inbound_seq: 1,
      outbound_seq: 2
    }

    ref2 =
      push(socket, "message", %{
        "message" => "Mensaje repetido",
        "client_msg_id" => client_msg_id
      })

    assert_reply ref2, :ok, %{
      status: "duplicate",
      client_msg_id: ^client_msg_id,
      inbound_seq: 1
    }
  end

  test "rechaza join sin token con error unauthorized" do
    session_id = Ecto.UUID.generate()

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
             |> Phoenix.ChannelTest.subscribe_and_join(
               LtpChatbotWeb.ConversationChannel,
               "conversation:#{session_id}",
               %{}
             )
  end

  test "rechaza join con token inválido o corrupto con error unauthorized" do
    session_id = Ecto.UUID.generate()

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
             |> Phoenix.ChannelTest.subscribe_and_join(
               LtpChatbotWeb.ConversationChannel,
               "conversation:#{session_id}",
               %{"token" => "token_invalido_corrupto"}
             )
  end

  test "rechaza join si el token pertenece a otra sesión diferente" do
    session_id1 = Ecto.UUID.generate()
    session_id2 = Ecto.UUID.generate()
    token_for_session2 = LtpChatbotWeb.SessionToken.sign(session_id2, "anon")

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
             |> Phoenix.ChannelTest.subscribe_and_join(
               LtpChatbotWeb.ConversationChannel,
               "conversation:#{session_id1}",
               %{"token" => token_for_session2}
             )
  end

  test "rechaza join a tópicos que no comiencen con conversation:" do
    token = LtpChatbotWeb.SessionToken.sign(Ecto.UUID.generate(), "anon")

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.socket(LtpChatbotWeb.UserSocket, "socket_id", %{})
             |> Phoenix.ChannelTest.subscribe_and_join(
               LtpChatbotWeb.ConversationChannel,
               "otro_topico:123",
               %{"token" => token}
             )
  end
end
