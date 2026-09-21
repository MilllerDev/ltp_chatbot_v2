defmodule LtpChatbotWebTest do
  use ExUnit.Case

  test "health response contract is available" do
    assert LtpChatbotAI.Inference.status() == :not_configured
  end
end
