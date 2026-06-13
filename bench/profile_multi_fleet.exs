Mix.Task.run("compile")
Code.require_file("bench/multi_fleet.ex", File.cwd!())

vehicles = String.to_integer(System.get_env("FLEET_VEHICLES", "4"))
gcs = String.to_integer(System.get_env("FLEET_GCS", "5"))
label = System.get_env("PROFILE_LABEL", "fleet-profile")
output = System.get_env("PROFILE_OUTPUT", "bench/results/profile-#{label}.txt")
base_port = String.to_integer(System.get_env("FLEET_BASE_PORT", "15800"))

MAVLink.Bench.MultiFleet.run_profile(
  vehicles: vehicles,
  gcs_count: gcs,
  base_port: base_port,
  label: label,
  output_file: output
)
