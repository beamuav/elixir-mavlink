defmodule MAVLink.Test.Utils do
  use ExUnit.Case
  import MAVLink.Utils
 
  test "x25 empty list" do
    assert x25_crc([]) == 0xffff
  end
  
  test "x25 empty binary" do
    assert x25_crc(<<>>) == 0xffff
  end
  
  test "x25 simple list" do
    assert x25_crc([1,2,3]) == 25284 # Checked against mavcrc.x25crc.accumulate()
  end
  
  test "x25 simple binary" do
    assert x25_crc("123") == 25419 # Checked against mavcrc.x25crc.accumulate_str()
  end
  
  test "x25 heartbeat seed" do
    assert x25_crc("HEARTBEAT ")
    |> x25_crc("uint32_t ")
    |> x25_crc("custom_mode ")
    |> x25_crc("uint8_t ")
    |> x25_crc("type ")
    |> x25_crc("uint8_t ")
    |> x25_crc("autopilot ")
    |> x25_crc("uint8_t ")
    |> x25_crc("base_mode ")
    |> x25_crc("uint8_t ")
    |> x25_crc("system_status ")
    |> x25_crc("uint8_t ")
    |> x25_crc("mavlink_version ")
    |> eight_bit_checksum() == 50 # Checked against mavgen
  end
  
  test "x25 change operator control seed" do
    assert x25_crc("CHANGE_OPERATOR_CONTROL ")
    |> x25_crc("uint8_t ")
    |> x25_crc("target_system ")
    |> x25_crc("uint8_t ")
    |> x25_crc("control_request ")
    |> x25_crc("uint8_t ")
    |> x25_crc("version ")
    |> x25_crc("char ")
    |> x25_crc("passkey ")
    |> x25_crc([25])
    |> eight_bit_checksum() == 217 # Checked against mavgen
  end
  
  test "parse ip address" do
    assert parse_ip_address("192.168.0.10") == {192, 168, 0, 10}
    assert parse_ip_address("127.0.0.1") == {127, 0, 0, 1}
    assert parse_ip_address("Burt") == {:error, :invalid_ip_address}
    assert parse_ip_address("192.168.1000.1") == {:error, :invalid_ip_address}
  end
  
end
