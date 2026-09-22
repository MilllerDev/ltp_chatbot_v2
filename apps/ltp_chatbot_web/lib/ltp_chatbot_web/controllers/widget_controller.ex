defmodule LtpChatbotWeb.WidgetController do
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  @doc """
  Renderiza la interfaz completa del widget conversacional dentro del iframe.
  Permite la incrustación desde cualquier origen (x-frame-options ALLOWALL).
  """
  def index(conn, params) do
    session_id = Map.get(params, "session_id") || Ecto.UUID.generate()

    html_content = render_widget_html(session_id)

    conn
    |> put_resp_header("x-frame-options", "ALLOWALL")
    |> put_resp_header("content-security-policy", "frame-ancestors *;")
    |> put_resp_header("access-control-allow-origin", "*")
    |> html(html_content)
  end

  @doc """
  Entrega el script cliente 'embed.js' para incrustar el chatbot con una sola línea de código:
  <script src="https://chat.latinpay.pe/widget/embed.js" defer></script>
  """
  def embed_js(conn, _params) do
    host = conn.host
    port = conn.port
    scheme = conn.scheme || :http
    
    # Determina la URL base del widget dinámicamente según el entorno
    base_url =
      if (scheme == :http and port == 80) or (scheme == :https and port == 443) do
        "#{scheme}://#{host}"
      else
        "#{scheme}://#{host}:#{port}"
      end

    js_code = """
    (function() {
      if (document.getElementById("ltp-chat-widget-root")) return;

      var root = document.createElement("div");
      root.id = "ltp-chat-widget-root";

      // Botón flotante de apertura
      var btn = document.createElement("button");
      btn.id = "ltp-chat-toggle-btn";
      btn.setAttribute("aria-label", "Abrir chat de soporte");
      btn.innerHTML = `
        <svg id="ltp-icon-open" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:block;margin:auto;">
          <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path>
        </svg>
        <svg id="ltp-icon-close" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="display:none;margin:auto;">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
      `;
      btn.style.cssText = "position:fixed;bottom:24px;right:24px;width:60px;height:60px;border-radius:50%;background:#0d6efd;color:#ffffff;border:none;box-shadow:0 8px 24px rgba(13,110,253,0.35);cursor:pointer;z-index:999999;transition:all 0.3s cubic-bezier(0.16,1,0.3,1);display:flex;align-items:center;justify-content:center;outline:none;";

      btn.onmouseenter = function() { btn.style.transform = "scale(1.08)"; };
      btn.onmouseleave = function() { btn.style.transform = "scale(1)"; };

      // Contenedor e iframe del chat
      var iframe = document.createElement("iframe");
      iframe.id = "ltp-chat-iframe";
      iframe.src = "#{base_url}/widget";
      iframe.title = "Chat de Soporte LatinPay";
      iframe.allow = "clipboard-write";
      iframe.style.cssText = "position:fixed;bottom:96px;right:24px;width:380px;height:580px;border:none;border-radius:16px;box-shadow:0 12px 48px rgba(0,0,0,0.18);z-index:999998;display:none;max-width:calc(100vw - 48px);max-height:calc(100vh - 120px);transform-origin:bottom right;transition:opacity 0.25s ease, transform 0.25s ease;";

      var isOpen = false;
      btn.onclick = function() {
        isOpen = !isOpen;
        if (isOpen) {
          iframe.style.display = "block";
          document.getElementById("ltp-icon-open").style.display = "none";
          document.getElementById("ltp-icon-close").style.display = "block";
          btn.style.background = "#334155";
        } else {
          iframe.style.display = "none";
          document.getElementById("ltp-icon-open").style.display = "block";
          document.getElementById("ltp-icon-close").style.display = "none";
          btn.style.background = "#0d6efd";
        }
      };

      root.appendChild(iframe);
      root.appendChild(btn);
      document.body.appendChild(root);
    })();
    """

    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_content_type("application/javascript")
    |> text(js_code)
  end

  # Plantilla HTML5 moderna, responsiva y autónoma (< 30 KB)
  defp render_widget_html(session_id) do
    """
    <!DOCTYPE html>
    <html lang="es">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>LTP Chat</title>
      <style>
        * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
        body { background: #f8fafc; display: flex; flex-direction: column; height: 100vh; overflow: hidden; color: #1e293b; }
        
        .chat-header {
          background: #0d6efd;
          color: #ffffff;
          padding: 16px 20px;
          display: flex;
          align-items: center;
          justify-content: space-between;
          box-shadow: 0 2px 8px rgba(13,110,253,0.15);
        }
        .chat-header .title-area { display: flex; flex-direction: column; gap: 2px; }
        .chat-header .title { font-weight: 700; font-size: 15px; letter-spacing: -0.2px; }
        .chat-header .status { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 500; opacity: 0.95; }
        .status-dot { width: 8px; height: 8px; border-radius: 50%; background: #22c55e; box-shadow: 0 0 6px #22c55e; }
        
        .chat-messages {
          flex: 1;
          padding: 20px;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
          gap: 12px;
          scroll-behavior: smooth;
        }
        .msg {
          max-width: 82%;
          padding: 12px 16px;
          border-radius: 16px;
          font-size: 14px;
          line-height: 1.45;
          word-break: break-word;
          box-shadow: 0 1px 3px rgba(0,0,0,0.06);
          animation: fadeIn 0.2s ease-out;
        }
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(6px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .msg.user {
          align-self: flex-end;
          background: #0d6efd;
          color: #ffffff;
          border-bottom-right-radius: 4px;
        }
        .msg.bot {
          align-self: flex-start;
          background: #ffffff;
          color: #1e293b;
          border-bottom-left-radius: 4px;
          border: 1px solid #e2e8f0;
        }
        .msg .time {
          font-size: 10px;
          opacity: 0.65;
          margin-top: 4px;
          text-align: right;
        }

        .chat-input-bar {
          padding: 14px 16px;
          background: #ffffff;
          border-top: 1px solid #e2e8f0;
          display: flex;
          align-items: center;
          gap: 10px;
        }
        .chat-input-bar input {
          flex: 1;
          padding: 11px 16px;
          border: 1px solid #cbd5e1;
          border-radius: 24px;
          outline: none;
          font-size: 14px;
          transition: border-color 0.2s;
        }
        .chat-input-bar input:focus {
          border-color: #0d6efd;
          box-shadow: 0 0 0 3px rgba(13,110,253,0.12);
        }
        .chat-input-bar button {
          background: #0d6efd;
          color: #ffffff;
          border: none;
          width: 40px;
          height: 40px;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          transition: background 0.2s, transform 0.1s;
        }
        .chat-input-bar button:hover { background: #0b5ed7; }
        .chat-input-bar button:active { transform: scale(0.95); }
      </style>
    </head>
    <body>
      <header class="chat-header">
        <div class="title-area">
          <div class="title">Asistente LTP</div>
          <div class="status"><span class="status-dot"></span> En línea</div>
        </div>
      </header>

      <main class="chat-messages" id="messages-box">
        <div class="msg bot">
          ¡Hola! Soy el asistente virtual de LatinPay. ¿En qué puedo ayudarte hoy?
          <div class="time">Ahora</div>
        </div>
      </main>

      <form class="chat-input-bar" id="chat-form">
        <input type="text" id="chat-input" placeholder="Escribe un mensaje..." autocomplete="off" required />
        <button type="submit" aria-label="Enviar mensaje">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="22" y1="2" x2="11" y2="13"></line>
            <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
          </svg>
        </button>
      </form>

      <!-- Cliente oficial Phoenix.js -->
      <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"></script>
      <script>
        (function() {
          // Persistencia del Session ID en LocalStorage
          var storageKey = "ltp_chat_session_id";
          var sessionId = localStorage.getItem(storageKey) || "#{session_id}";
          localStorage.setItem(storageKey, sessionId);

          var messagesBox = document.getElementById("messages-box");
          var form = document.getElementById("chat-form");
          var input = document.getElementById("chat-input");

          function formatTime() {
            var d = new Date();
            return d.getHours().toString().padStart(2, "0") + ":" + d.getMinutes().toString().padStart(2, "0");
          }

          function appendMessage(sender, text) {
            var msgDiv = document.createElement("div");
            msgDiv.className = "msg " + sender;
            msgDiv.innerHTML = text.replace(/\\n/g, "<br/>") + '<div class="time">' + formatTime() + '</div>';
            messagesBox.appendChild(msgDiv);
            messagesBox.scrollTop = messagesBox.scrollHeight;
          }

          // Conexión WebSocket mediante Phoenix.Socket
          var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
          var socketUrl = protocol + "//" + window.location.host + "/socket";
          var socket = new Phoenix.Socket(socketUrl, { params: { session_id: sessionId } });
          socket.connect();

          // Unión al canal de conversación en tiempo real
          var channel = socket.channel("conversation:" + sessionId, {});

          channel.join()
            .receive("ok", function(resp) {
              console.log("[LTP Chat] Conectado al canal con éxito", resp);
            })
            .receive("error", function(resp) {
              console.error("[LTP Chat] Error al conectar al canal", resp);
            });

          // Recepción de respuestas del servidor
          channel.on("reply", function(payload) {
            if (payload && payload.text) {
              appendMessage("bot", payload.text);
            }
          });

          // Envío de mensajes del usuario
          form.onsubmit = function(e) {
            e.preventDefault();
            var text = input.value.trim();
            if (!text) return;

            appendMessage("user", text);
            input.value = "";

            var clientMsgId = (window.crypto && window.crypto.randomUUID) 
              ? window.crypto.randomUUID() 
              : "msg_" + Date.now();

            channel.push("message", {
              message: text,
              client_msg_id: clientMsgId
            });
          };
        })();
      </script>
    </body>
    </html>
    """
  end
end
