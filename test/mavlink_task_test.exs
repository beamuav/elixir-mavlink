defmodule MavlinkTest do
  use ExUnit.Case
  import Mix.Tasks.Mavlink
 
  test "generate" do
    root_dir = File.cwd!
    IO.puts run(["generate", "#{root_dir}/test/mavlink.xml"])
  end
end
