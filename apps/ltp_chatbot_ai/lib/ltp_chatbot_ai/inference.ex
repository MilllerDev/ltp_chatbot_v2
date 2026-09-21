defmodule LtpChatbotAI.Inference do
  @moduledoc """
  Stable boundary for model inference.

  Model loading is intentionally disabled in the initial foundation. This
  keeps boot and tests deterministic while allowing the web layer to depend on
  a small, replaceable contract.
  """

  @type response :: {:ok, map()} | {:error, :not_configured}

  @spec status() :: :not_configured
  def status, do: :not_configured

  @spec generate(String.t(), keyword()) :: response()
  def generate(_prompt, _opts \\ []), do: {:error, :not_configured}
end
