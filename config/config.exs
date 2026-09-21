import Config

config :phoenix, :json_library, Jason
config :phoenix, :plug_init_mode, :runtime

config :ltp_chatbot, ecto_repos: [LtpChatbot.Repo]

config :ltp_chatbot_web,
  generators: [context_app: :ltp_chatbot]

import_config "#{config_env()}.exs"
