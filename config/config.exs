use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udp:192.168.0.23:14550", "udp:127.0.0.1:14550"]
config :logger, level: :info
