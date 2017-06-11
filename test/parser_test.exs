defmodule DefinitionsTest do
  use ExUnit.Case
  import Mavlink.Parser

  @root_dir File.cwd!

  test "parse definitions" do
    IO.inspect parse_definitions(
      "#{@root_dir}/config/common.xml")
  end
end
