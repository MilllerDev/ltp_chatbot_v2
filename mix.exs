defmodule LtpChatbot.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def aliases do
    [
      setup: ["deps.get", "ecto.create", "ecto.migrate"],
      ci: ["format --check-formatted", "compile --warnings-as-errors", "test"]
    ]
  end

  defp deps do
    []
  end
end
