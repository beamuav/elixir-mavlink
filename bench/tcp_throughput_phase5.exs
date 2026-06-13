Mix.Task.run("compile")
Code.require_file("bench/tcp_throughput.ex", File.cwd!())

MAVLink.Bench.TCPThroughput.run(
  output_file: "bench/results/after-phase5.txt",
  label: "after-phase5"
)
