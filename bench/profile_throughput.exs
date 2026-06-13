Mix.Task.run("compile")
Code.require_file("bench/profile_throughput.ex", File.cwd!())

label = System.get_env("PROFILE_LABEL", "current")
output = System.get_env("PROFILE_OUTPUT", "bench/results/profile-#{label}.txt")

MAVLink.Bench.ProfileThroughput.run(label: label, output_file: output)
