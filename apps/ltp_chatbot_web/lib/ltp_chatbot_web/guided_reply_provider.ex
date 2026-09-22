defmodule LtpChatbotWeb.GuidedReplyProvider do
  @moduledoc "Temporary deterministic responder used before the AI engine."

  @behaviour LtpChatbotWeb.ReplyProvider

  @impl true
  def reply(%{text: text}) do
    {:ok,
     %{
       "text" =>
         "¡Hola! He recibido tu mensaje: \"#{text}\". El servidor Phoenix está respondiendo en vivo."
     }}
  end
end
