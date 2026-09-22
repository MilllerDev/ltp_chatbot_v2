defmodule LtpChatbotWeb.WidgetController do
  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias LtpChatbotWeb.{ConversationService, WidgetRenderer}

  def index(conn, params) do
    origin = List.first(get_req_header(conn, "origin")) || conn.host

    case ConversationService.ensure_session(Map.get(params, "session_id"), origin) do
      {:ok, session_id} ->
        conn
        |> put_resp_header("x-frame-options", "ALLOWALL")
        |> put_resp_header("content-security-policy", "frame-ancestors *;")
        |> put_resp_header("access-control-allow-origin", "*")
        |> html(WidgetRenderer.render(session_id, reuse_local_storage: is_nil(Map.get(params, "session_id"))))

      {:error, _reason} -> send_resp(conn, :unprocessable_entity, "invalid session")
    end
  end

  def embed_js(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/javascript")
    |> text(WidgetRenderer.embed_script(endpoint_base_url(conn)))
  end

  defp endpoint_base_url(conn) do
    scheme = conn.scheme || :http

    if (scheme == :http and conn.port == 80) or (scheme == :https and conn.port == 443) do
      "#{scheme}://#{conn.host}"
    else
      "#{scheme}://#{conn.host}:#{conn.port}"
    end
  end
end
