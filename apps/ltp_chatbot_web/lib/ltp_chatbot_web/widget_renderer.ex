defmodule LtpChatbotWeb.WidgetRenderer do
  @moduledoc "Presentation layer for the embeddable chat widget."

  def render(session_id, options \\ []) do
    encoded_session_id = Jason.encode!(session_id)
    reuse_local_storage = Keyword.get(options, :reuse_local_storage, false)

    """
    <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>LTP Chat</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      body { background: #f8fafc; display: flex; flex-direction: column; height: 100vh; overflow: hidden; color: #1e293b; }
      .chat-header { background: #0d6efd; color: #fff; padding: 16px 20px; }
      .title { font-weight: 700; font-size: 15px; } .status { display: flex; align-items: center; gap: 6px; font-size: 12px; margin-top: 3px; }
      .status::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: #f59e0b; box-shadow: 0 0 6px rgba(245,158,11,.7); }
      .status.online::before { background: #22c55e; box-shadow: 0 0 7px rgba(34,197,94,.9); }
      .status.offline::before { background: #ef4444; box-shadow: 0 0 7px rgba(239,68,68,.75); }
      .chat-messages { flex: 1; padding: 20px; overflow-y: auto; display: flex; flex-direction: column; gap: 12px; }
      .msg { max-width: 82%; padding: 12px 16px; border-radius: 16px; font-size: 14px; line-height: 1.45; word-break: break-word; }
      .msg.user { align-self: flex-end; background: #0d6efd; color: #fff; border-bottom-right-radius: 4px; }
      .msg.bot { align-self: flex-start; background: #fff; border: 1px solid #e2e8f0; border-bottom-left-radius: 4px; }
      .time { font-size: 10px; opacity: .65; margin-top: 4px; text-align: right; }
      .chat-input-bar { padding: 14px 16px; background: #fff; border-top: 1px solid #e2e8f0; display: flex; gap: 10px; }
      .chat-input-bar input { flex: 1; padding: 11px 16px; border: 1px solid #cbd5e1; border-radius: 24px; outline: none; font-size: 14px; }
      .chat-input-bar button { background: #0d6efd; color: #fff; border: 0; width: 40px; height: 40px; border-radius: 50%; cursor: pointer; }
    </style></head><body>
      <header class="chat-header"><div class="title">Asistente LTP</div><div class="status">● En línea</div></header>
      <main class="chat-messages" id="messages-box"></main>
      <form class="chat-input-bar" id="chat-form"><input type="text" id="chat-input" placeholder="Escribe un mensaje..." autocomplete="off" required /><button type="submit" aria-label="Enviar mensaje">➤</button></form>
      <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"></script><script>
        (function() {
          var serverSessionId = #{encoded_session_id}, reuseLocalStorage = #{reuse_local_storage}, sessionKey = "ltp_chat_session_id", sessionId = serverSessionId;
          if (reuseLocalStorage) { try { sessionId = localStorage.getItem(sessionKey) || serverSessionId; localStorage.setItem(sessionKey, sessionId); } catch (error) { sessionId = serverSessionId; } }
          var lastSeq = 0, box = document.getElementById("messages-box"), form = document.getElementById("chat-form"), input = document.getElementById("chat-input"), status = document.querySelector(".status");
          function setConnection(connected) { status.className = "status " + (connected ? "online" : "offline"); status.textContent = connected ? "En línea" : "Desconectado"; }
          function rememberSeq(seq) { if (typeof seq === "number" && seq > lastSeq) lastSeq = seq; }
          function appendMessage(direction, text, seq) {
            var msg = document.createElement("div"), content = document.createElement("div"), time = document.createElement("div");
            msg.className = "msg " + (direction === "in" ? "user" : "bot"); content.textContent = text || ""; time.className = "time"; time.textContent = seq ? "#" + seq : "Ahora";
            msg.appendChild(content); msg.appendChild(time); box.appendChild(msg); box.scrollTop = box.scrollHeight; rememberSeq(seq);
          }
          function paint(event) { var body = event && event.body ? event.body : {}; appendMessage(event.direction, body.text || "", event.seq); }
          var protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
          var socket = new Phoenix.Socket(protocol + "//" + window.location.host + "/socket", { params: { session_id: sessionId } });
          socket.onOpen(function() { setConnection(true); }); socket.onClose(function() { setConnection(false); }); socket.onError(function() { setConnection(false); }); socket.connect();
          var channel = socket.channel("conversation:" + sessionId, { last_seq: 0 });
          channel.join().receive("ok", function(resp) { setConnection(true); (resp.messages || []).forEach(paint); rememberSeq(resp.last_seq); }).receive("error", function() { setConnection(false); });
          channel.on("reply", function(payload) { if (payload && payload.outbound) paint(payload.outbound); });
          form.onsubmit = function(event) {
            event.preventDefault(); var text = input.value.trim(); if (!text) return;
            var clientMsgId = window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : "msg_" + Date.now();
            appendMessage("in", text); input.value = "";
            channel.push("message", { message: text, client_msg_id: clientMsgId }).receive("ok", function(resp) { rememberSeq(resp.inbound_seq); rememberSeq(resp.outbound_seq); });
          };
        })();
      </script></body></html>
    """
  end

  def embed_script(base_url) do
    encoded_url = Jason.encode!(base_url <> "/widget")

    """
    (function() { if (document.getElementById("ltp-chat-widget-root")) return;
      var root = document.createElement("div"), button = document.createElement("button"), iframe = document.createElement("iframe"), sessionKey = "ltp_chat_session_id", sessionId;
      try { sessionId = localStorage.getItem(sessionKey) || (window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : "session_" + Date.now()); localStorage.setItem(sessionKey, sessionId); } catch (error) { sessionId = window.crypto && window.crypto.randomUUID ? window.crypto.randomUUID() : "session_" + Date.now(); }
      root.id = "ltp-chat-widget-root"; button.id = "ltp-chat-toggle-btn"; button.setAttribute("aria-label", "Abrir chat de soporte"); button.textContent = "💬";
      button.style.cssText = "position:fixed;bottom:24px;right:24px;width:60px;height:60px;border-radius:50%;background:#0d6efd;color:#fff;border:0;box-shadow:0 8px 24px rgba(13,110,253,.35);cursor:pointer;z-index:999999;font-size:26px;";
      iframe.id = "ltp-chat-iframe"; iframe.src = #{encoded_url} + "?session_id=" + encodeURIComponent(sessionId); iframe.title = "Chat de Soporte LatinPay";
      iframe.style.cssText = "position:fixed;bottom:96px;right:24px;width:380px;height:580px;border:0;border-radius:16px;box-shadow:0 12px 48px rgba(0,0,0,.18);z-index:999998;display:none;max-width:calc(100vw - 48px);max-height:calc(100vh - 120px);";
      button.onclick = function() { iframe.style.display = iframe.style.display === "none" ? "block" : "none"; }; root.appendChild(iframe); root.appendChild(button); document.body.appendChild(root);
    })();
    """
  end
end
