defmodule MAVLink.Test.DialectFixture do
  @moduledoc false

  @output "#{File.cwd!()}/test/output/test_mavlink.ex"
  @input "#{File.cwd!()}/test/input/test_mavlink.xml"

  def ensure_compiled! do
    unless File.exists?(@output) do
      File.mkdir_p(Path.dirname(@output))
      Mix.Task.run("mavlink", [@input, @output, "TestMavlink"])
    end

    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_file(@output)
    TestMavlink
  end
end
