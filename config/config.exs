use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udp:192.168.20.6:14550"]
config :logger, level: :info
