defmodule LtpChatbot.ConversationsTest do
  use ExUnit.Case, async: false

  alias LtpChatbot.Conversations
  alias LtpChatbot.Sessions.Session

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(LtpChatbot.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(LtpChatbot.Repo, {:shared, self()})
    :ok
  end

  describe "get_or_create_session/2" do
    test "crea una sesión nueva con UUID generado cuando se envía nil" do
      assert {:ok, %Session{} = session, :created} =
               Conversations.get_or_create_session(nil, %{origin: "localhost"})

      assert is_binary(session.id)
      assert session.last_seq == 0
      assert session.origin == "localhost"
    end

    test "crea una sesión con UUID específico y la reutiliza en llamadas subsecuentes" do
      custom_id = Ecto.UUID.generate()

      assert {:ok, session1, :created} =
               Conversations.get_or_create_session(custom_id, %{origin: "web"})

      assert session1.id == custom_id

      assert {:ok, session2, :existing} =
               Conversations.get_or_create_session(custom_id, %{origin: "web"})

      assert session2.id == custom_id
    end

    test "rechaza session_id que no tenga formato UUID válido" do
      assert {:error, :invalid_session_id} =
               Conversations.get_or_create_session("not-a-uuid", %{origin: "web"})
    end
  end

  describe "append_message/4" do
    test "inserta mensajes secuenciales e incrementa last_seq con bloqueo atómico" do
      {:ok, session, :created} =
        Conversations.get_or_create_session(nil, %{origin: "web"})

      client_msg_id1 = Ecto.UUID.generate()
      client_msg_id2 = Ecto.UUID.generate()

      assert {:ok, :inserted, msg1} =
               Conversations.append_message(
                 session.id,
                 :in,
                 %{"text" => "Primer mensaje"},
                 client_msg_id1
               )

      assert msg1.seq == 1
      assert msg1.client_msg_id == client_msg_id1

      assert {:ok, :inserted, msg2} =
               Conversations.append_message(
                 session.id,
                 :out,
                 %{"text" => "Respuesta"},
                 client_msg_id2
               )

      assert msg2.seq == 2

      # Verificar que el session.last_seq se actualizó en BD
      updated_session = Conversations.get_session(session.id)
      assert updated_session.last_seq == 2
    end

    test "detecta y previene duplicados cuando se reenvía el mismo client_msg_id" do
      {:ok, session, :created} =
        Conversations.get_or_create_session(nil, %{origin: "web"})

      client_msg_id = Ecto.UUID.generate()

      assert {:ok, :inserted, msg1} =
               Conversations.append_message(
                 session.id,
                 :in,
                 %{"text" => "Mensaje original"},
                 client_msg_id
               )

      assert msg1.seq == 1

      # Segundo intento con el mismo client_msg_id (idempotencia)
      assert {:ok, :duplicate, msg2} =
               Conversations.append_message(
                 session.id,
                 :in,
                 %{"text" => "Mensaje repetido"},
                 client_msg_id
               )

      assert msg2.session_id == msg1.session_id
      assert msg2.seq == msg1.seq

      # El last_seq no debe haberse incrementado
      updated_session = Conversations.get_session(session.id)
      assert updated_session.last_seq == 1
    end
  end

  describe "messages_after/2" do
    test "obtiene mensajes después de un seq determinado ordenados ascendentemente" do
      {:ok, session, :created} =
        Conversations.get_or_create_session(nil, %{origin: "web"})

      {:ok, :inserted, _} =
        Conversations.append_message(session.id, :in, %{"text" => "m1"}, Ecto.UUID.generate())

      {:ok, :inserted, _} =
        Conversations.append_message(session.id, :out, %{"text" => "m2"}, Ecto.UUID.generate())

      {:ok, :inserted, _} =
        Conversations.append_message(session.id, :in, %{"text" => "m3"}, Ecto.UUID.generate())

      assert {:ok, messages} = Conversations.messages_after(session.id, 1)
      assert length(messages) == 2
      assert Enum.map(messages, & &1.seq) == [2, 3]
    end
  end
end
