import Config

config :ltp_chatbot, LtpChatbot.Repo,
  username: System.get_env("POSTGRES_USER", "ltp_chatbot"),
  password: System.get_env("POSTGRES_PASSWORD", "ltp_chatbot"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "ltp_chatbot_dev"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ltp_chatbot_web, LtpChatbotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: []

config :logger, :console, format: "[$level] $message\n"
