defmodule LtpChatbotTest do
  use ExUnit.Case

  test "the domain application is available" do
    assert LtpChatbot.Conversations.health_check() == :ok
  end
end
