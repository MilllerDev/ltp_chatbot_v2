defmodule LtpChatbotWeb.MixProject do
  use Mix.Project

  def project do
    [app: :ltp_chatbot_web, version: "0.1.0", build_path: "../../_build", deps_path: "../../deps", lockfile: "../../mix.lock", deps: deps()]
  end

  def application do
    [extra_applications: [:logger], mod: {LtpChatbotWeb.Application, []}]
  end

  defp deps do
    [
      {:ltp_chatbot, in_umbrella: true},
      {:ltp_chatbot_ai, in_umbrella: true},
      {:ltp_chatbot_wa, in_umbrella: true},
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"}
    ]
  end
end
