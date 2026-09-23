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
  http: [
    ip: {0, 0, 0, 0},
    port: String.to_integer(System.get_env("PORT", "4000")),
    protocol_options: [
      max_header_value_length: 32_768,
      max_header_name_length: 2_048,
      max_headers: 200
    ]
  ],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  secret_key_base: "m7q0Z9P1eR4xS8uY2wK5vM3nT6jH1gF8dS9aD2fG5hJ7kL4zX6cE1vB8nQ3wR5tY",
  watchers: []

config :logger, :console, format: "[$level] $message\n"
