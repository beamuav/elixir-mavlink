defmodule DefinitionsTest do
  use ExUnit.Case
  use Mavlink.Definitions

  @root_dir File.cwd!

  test "load definitions" do
    IO.inspect load_definitions("#{@root_dir}/config/common.xml")
  end
end
