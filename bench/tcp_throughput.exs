Mix.Task.run("compile")
Code.require_file("bench/tcp_throughput.ex", File.cwd!())
MAVLink.Bench.TCPThroughput.run()
