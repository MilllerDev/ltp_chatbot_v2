defmodule LtpChatbotWeb.ReplyProvider do
  @moduledoc "Contract for generating a response to an inbound message."

  @callback reply(%{text: String.t(), session_id: Ecto.UUID.t()}) ::
              {:ok, %{text: String.t()}} | {:error, term()}
end
