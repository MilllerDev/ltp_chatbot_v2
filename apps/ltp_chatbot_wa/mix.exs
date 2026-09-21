defmodule LtpChatbotWA.MixProject do
  use Mix.Project

  def project do
    [
      app: :ltp_chatbot_wa,
      version: "0.1.0",
      build_path: "../../_build",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {LtpChatbotWA.Application, []}
    ]
  end

  defp deps do
    [
      {:ltp_chatbot, in_umbrella: true},
      {:broadway, "~> 1.1"},
      {:finch, "~> 0.19"},
      {:jason, "~> 1.4"}
    ]
  end
end
