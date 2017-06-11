defmodule ParserTest do
  use ExUnit.Case
  import Mavlink.Parser

  @root_dir File.cwd!

  test "parse mavlink XML" do
    parse_mavlink_xml("#{@root_dir}/config/common.xml")
  end
  
end
