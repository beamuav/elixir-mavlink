defmodule MAVLink.Test.LocalConnectionTest do
  use ExUnit.Case, async: false

  alias MAVLink.LocalConnection
  alias MAVLink.Test.DialectFixture
  import MAVLink.Test.FrameFixtures

  setup do
    {:ok, dialect: DialectFixture.ensure_compiled!()}
  end

  test "subscribe and forward matching heartbeat", %{dialect: _dialect} do
    lc = %LocalConnection{system: 245, component: 250, subscriptions: [], sequence_number: 0}
    subscriber = self()
    lc = LocalConnection.subscribe(%{message: TestMavlink.Message.Heartbeat, source_system: 1, source_component: 0, target_system: 0, target_component: 0, as_frame: false}, subscriber, lc)
    frame =
      heartbeat_frame(source_system: 1, source_component: 1)
      |> Map.put(:message, struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic]))

    LocalConnection.forward(lc, frame)
    assert_receive msg, 100
    assert msg.__struct__ == TestMavlink.Message.Heartbeat
  end

  test "as_frame delivers frame struct" do
    lc = %LocalConnection{system: 245, component: 250, subscriptions: [], sequence_number: 0}
    subscriber = self()
    lc = LocalConnection.subscribe(%{message: nil, source_system: 0, source_component: 0, target_system: 0, target_component: 0, as_frame: true}, subscriber, lc)
    frame = heartbeat_frame()

    LocalConnection.forward(lc, frame)
    assert_receive %MAVLink.Frame{}, 100
  end

  test "sequence number increments on local handle_info" do
    lc = %LocalConnection{system: 245, component: 250, subscriptions: [], sequence_number: 10}
    frame = Map.drop(heartbeat_frame(), [:mavlink_1_raw, :mavlink_2_raw])

    assert {:ok, :local, updated, packed} = LocalConnection.handle_info({:local, frame}, lc, TestMavlink)
    assert updated.sequence_number == 11
    assert packed.sequence_number == 10
  end

  test "unsubscribe removes subscriber" do
    lc = %LocalConnection{system: 245, component: 250, subscriptions: [], sequence_number: 0}
    subscriber = self()
    lc = LocalConnection.subscribe(%{}, subscriber, lc)
    lc = LocalConnection.unsubscribe(subscriber, lc)
    assert lc.subscriptions == []
  end
end
