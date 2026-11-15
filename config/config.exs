import Config

config :emergencias, data_path: "data/emergencias.txt"

import_config "#{config_env()}.exs"
