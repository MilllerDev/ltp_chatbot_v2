import Config

config :ltp_chatbot, LtpChatbot.Repo,
  username: System.get_env("POSTGRES_USER", "ltp_chatbot"),
  password: System.get_env("POSTGRES_PASSWORD", "ltp_chatbot"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: "ltp_chatbot_test",
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :ltp_chatbot_web, LtpChatbotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false

config :logger, level: :warning
