use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udp:127.0.0.1:49000"]
config :logger, level: :info
