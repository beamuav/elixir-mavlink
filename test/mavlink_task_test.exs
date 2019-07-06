defmodule Mavlink.Test.Tasks do
  use ExUnit.Case
  import Mix.Tasks.Mavlink
  
  @input "#{File.cwd!}/test/input/common.xml"
  @output "#{File.cwd!}/lib/Mavlink.ex"
 
  test "generate" do
    #File.rm(@output)
    run([
      "generate",
      @input,
      @output])
    assert File.exists?(@output)
    assert [Mavlink] =
      Code.compile_file(@output)
      |> Keyword.keys
      |> Enum.sort()
  end
  
end
