defmodule MAVLink.Test.Tasks do
  use ExUnit.Case
  import Mix.Tasks.Mavlink

  @input "#{File.cwd!()}/test/input/test_mavlink.xml"
  @output_dir "#{File.cwd!()}/test/output"
  @output "#{@output_dir}/test_mavlink.ex"
  @output_module "TestMavlink"

  test "generate" do
    # Setup output directory
    File.mkdir_p(@output_dir)
    File.rm(@output)

    # Run mix task
    run([@input, @output, @output_module])

    # Did it generate
    assert File.exists?(@output)

    # We don't care if we redefine MAVLink modules while running the following test
    Code.compiler_options(ignore_module_conflict: true)

    # Confirm the list of modules generated from common.xml and its includes
    pairs = Enum.zip(
      [
        MAVLink.Message.TestMavlink.Message.ChangeOperatorControl,
        MAVLink.Message.TestMavlink.Message.Data16,
        MAVLink.Message.TestMavlink.Message.Heartbeat,
        MAVLink.Message.TestMavlink.Message.VfrHud,
        TestMavlink,
        TestMavlink.Message.ChangeOperatorControl,
        TestMavlink.Message.Data16,
        TestMavlink.Message.Heartbeat,
        TestMavlink.Message.VfrHud,
        TestMavlink.Types],
      Code.compile_file(@output)
      |> Keyword.keys()
      |> Enum.sort()
    )

    for {expected, actual} <- pairs do
      assert expected == actual
    end
    
  end
end
