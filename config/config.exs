use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udpin:192.168.0.14:14550"] # APM
config :mavlink, connections: ["tcpout:192.168.0.14:5760"] # SITL
config :logger, level: :debug
