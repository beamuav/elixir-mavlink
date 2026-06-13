defmodule MAVLink.FrameTest do
  use ExUnit.Case, async: false

  alias MAVLink.Frame
  alias MAVLink.Test.{DialectFixture, FrameFixtures}

  setup do
    dialect = DialectFixture.ensure_compiled!()
    Application.put_env(:mavlink, :dialect, dialect)
    {:ok, dialect: dialect}
  end

  test "computed checksum matches binary and legacy list paths", %{dialect: dialect} do
    raw = FrameFixtures.heartbeat_v2_raw()
    {frame, <<>>} = Frame.binary_to_frame_and_tail(raw)

    assert {:ok, crc_extra, _, _} = apply(dialect, :msg_attributes, [frame.message_id])

    binary_crc =
      raw
      |> binary_part(1, frame.payload_length + 9)
      |> MAVLink.Utils.x25_crc()
      |> MAVLink.Utils.x25_crc(<<crc_extra::unsigned-integer-size(8)>>)

    list_crc =
      :binary.bin_to_list(raw, {1, frame.payload_length + 9})
      |> MAVLink.Utils.x25_crc()
      |> MAVLink.Utils.x25_crc([crc_extra])

    assert binary_crc == list_crc
    assert frame.checksum == binary_crc
    assert {:ok, _} = Frame.validate_checksum(frame, dialect)
  end

  test "prepare_for_route skips unpack for as_raw subscribers", %{dialect: dialect} do
    {:ok, _} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)

    on_exit(fn ->
      if Process.whereis(MAVLink.RouteTable), do: GenServer.stop(MAVLink.RouteTable)
    end)

    :ok =
      MAVLink.RouteTable.subscribe(
        %{
          message: TestMavlink.Message.VfrHud,
          source_system: 0,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false,
          as_raw: true
        },
        self()
      )

    raw = FrameFixtures.vfr_hud_v2_raw(source_system: 2)
    {frame, <<>>} = Frame.binary_to_frame_and_tail(raw)

    assert {:ok, routed} = Frame.prepare_for_route(frame, dialect)
    assert routed.message == nil
    assert routed.target == :broadcast
    assert routed.crc_extra == 20
  end

  test "data16 array field unpacks via bitstring comprehension", %{dialect: dialect} do
    raw = FrameFixtures.data16_v2_raw(data: :binary.copy(<<0xAB>>, 16))
    {frame, <<>>} = Frame.binary_to_frame_and_tail(raw)

    assert {:ok, unpacked} = Frame.validate_and_unpack(frame, dialect)
    assert unpacked.message.data == List.duplicate(0xAB, 16)
  end
end
