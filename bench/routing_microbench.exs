Mix.Task.run("compile")
Code.require_file("bench/routing_microbench.ex", File.cwd!())

MAVLink.Bench.RoutingMicrobench.run(
  label: System.get_env("ROUTING_LABEL", "routing"),
  output_file: System.get_env("ROUTING_OUTPUT", "bench/results/routing-#{System.get_env("ROUTING_LABEL", "routing")}.txt"),
  subscribers: String.to_integer(System.get_env("ROUTING_SUBSCRIBERS", "50")),
  frames: String.to_integer(System.get_env("ROUTING_FRAMES", "100000"))
)
