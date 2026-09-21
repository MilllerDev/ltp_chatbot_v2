defmodule LtpChatbotAI.MixProject do
  use Mix.Project

  def project do
    [app: :ltp_chatbot_ai, version: "0.1.0", build_path: "../../_build", deps_path: "../../deps", lockfile: "../../mix.lock", deps: deps()]
  end

  def application do
    [extra_applications: [:logger], mod: {LtpChatbotAI.Application, []}]
  end

  defp deps do
    [
      {:bumblebee, "~> 0.6.3"},
      {:nx, "~> 0.9"}
    ]
  end
end
