defmodule LtpChatbot.Conversations do
  @moduledoc """
  Context boundary for conversations and messages.

  Persistence operations will be added here so the web layer does not depend
  directly on schemas or Ecto queries.
  """

  @spec health_check() :: :ok
  def health_check, do: :ok
end
