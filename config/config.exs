import Config

config :phoenix, :json_library, Jason
config :phoenix, :plug_init_mode, :runtime

config :ltp_chatbot, ecto_repos: [LtpChatbot.Repo]

config :ltp_chatbot_web,
  generators: [context_app: :ltp_chatbot]

config :ltp_chatbot_web, LtpChatbotWeb.Endpoint,
  pubsub_server: LtpChatbotWeb.PubSub,
  render_errors: [formats: [json: LtpChatbotWeb.ErrorJSON], layout: false]

import_config "#{config_env()}.exs"
