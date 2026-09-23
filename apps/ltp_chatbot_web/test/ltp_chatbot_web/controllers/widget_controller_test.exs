defmodule LtpChatbotWeb.WidgetControllerTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint LtpChatbotWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(LtpChatbot.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(LtpChatbot.Repo, {:shared, self()})
    :ok
  end

  test "GET /widget entrega HTML 200 con cabeceras de iframe y session_id" do
    conn = build_conn() |> get("/widget")
    response_body = html_response(conn, 200)

    assert response_body =~ "Asistente LTP"
    assert response_body =~ "Phoenix.Socket"
    assert response_body =~ "chat-messages"
    assert response_body =~ "serverToken"
    assert response_body =~ "tokenKey"
    assert get_resp_header(conn, "x-frame-options") == ["ALLOWALL"]
    assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors *;"]
  end

  test "GET /widget/embed.js entrega script JavaScript con cabeceras CORS" do
    conn = build_conn() |> get("/widget/embed.js")
    response_body = response(conn, 200)

    assert response_body =~ "ltp-chat-widget-root"
    assert response_body =~ "ltp-chat-iframe"
    assert response_body =~ "ltp-chat-toggle-btn"
    assert response_content_type(conn, :js) =~ "application/javascript"
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
  end
end
