Mix.Task.run("compile")
Code.require_file("bench/multi_fleet.ex", File.cwd!())

vehicles = String.to_integer(System.get_env("FLEET_VEHICLES", "4"))
gcs = String.to_integer(System.get_env("FLEET_GCS", "5"))
label = System.get_env("FLEET_LABEL", "fleet")
output = System.get_env("FLEET_OUTPUT", "bench/results/#{label}.txt")

MAVLink.Bench.MultiFleet.run_throughput(
  vehicles: vehicles,
  gcs_count: gcs,
  label: label,
  output_file: output
)
