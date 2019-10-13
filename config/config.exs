use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udp:192.168.0.14:14550"]
config :logger, level: :info
