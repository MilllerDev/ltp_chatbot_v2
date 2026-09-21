defmodule LtpChatbotAITest do
  use ExUnit.Case

  test "does not load a model by default" do
    assert LtpChatbotAI.Inference.status() == :not_configured
    assert LtpChatbotAI.Inference.generate("hello") == {:error, :not_configured}
  end
end
