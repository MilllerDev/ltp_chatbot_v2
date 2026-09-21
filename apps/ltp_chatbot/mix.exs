defmodule LtpChatbot.MixProject do
  use Mix.Project

  def project do
    [app: :ltp_chatbot, version: "0.1.0", build_path: "../../_build", deps_path: "../../deps", lockfile: "../../mix.lock", deps: deps()]
  end

  def application do
    [extra_applications: [:logger], mod: {LtpChatbot.Application, []}]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"}
    ]
  end
end
