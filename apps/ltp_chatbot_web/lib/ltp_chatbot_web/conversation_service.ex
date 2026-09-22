defmodule LtpChatbotWeb.ConversationService do
  @moduledoc "Application service between Phoenix transport and session domain."

  alias LtpChatbot.Conversations
  alias LtpChatbot.Sessions.SessionServer
  alias LtpChatbotWeb.MessageSerializer

  def ensure_session(session_id, origin) do
    case Conversations.get_or_create_session(session_id, %{tier: "anon", origin: origin}) do
      {:ok, session, _status} -> {:ok, session.id}
      {:error, reason} -> {:error, reason}
    end
  end

  def resume(session_id, last_seq) do
    with {:ok, messages} <- SessionServer.resume(session_id, last_seq) do
      {:ok, Enum.map(messages, &MessageSerializer.serialize/1)}
    end
  end

  def handle_message(session_id, client_msg_id, text) do
    with {:ok, :inserted, inbound} <-
           SessionServer.inbound(session_id, client_msg_id, %{"text" => text}),
         {:ok, reply_body} <-
           apply(reply_provider(), :reply, [%{text: text, session_id: session_id}]),
         {:ok, outbound} <- SessionServer.append_outbound(session_id, reply_body) do
      {:ok,
       %{
         status: "delivered",
         inbound: MessageSerializer.serialize(inbound),
         outbound: MessageSerializer.serialize(outbound)
       }}
    else
      {:ok, :duplicate, inbound} ->
        {:ok, %{status: "duplicate", inbound: MessageSerializer.serialize(inbound)}}

      {:error, reason} -> {:error, reason}
    end
  end

  defp reply_provider do
    Application.get_env(:ltp_chatbot_web, :reply_provider, LtpChatbotWeb.GuidedReplyProvider)
  end
end
