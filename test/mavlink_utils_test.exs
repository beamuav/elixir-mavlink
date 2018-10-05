defmodule MavlinkTest do
  use ExUnit.Case
  import Mavlink.Utils
 
  test "x25 empty list" do
    assert x25_crc([]) == 0xffff
  end
  
  test "x25 empty binary" do
    assert x25_crc(<<>>) == 0xffff
  end
  
  test "x25 simple list" do
    assert x25_crc([1,2,3]) == 38785
  end
  
   test "x25 simple binary" do
    assert x25_crc("123") == 34701
  end
end
