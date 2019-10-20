use Mix.Config

config :mavlink, dialect: APM
config :mavlink, connections: ["udpin:192.168.0.14:15550", "udpout:127.0.0.1:14550", "tcpout:127.0.0.1:5760"] # APM, QGC (HAS to be loopback), SITL
config :logger, level: :error
