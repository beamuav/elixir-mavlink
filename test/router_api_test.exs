defmodule MAVLink.Test.RouterAPITest do
  use MAVLink.Test.RouterCase, async: false

  test "subscribe with invalid message returns error" do
    assert {:error, :invalid_message} = MAVLink.Router.subscribe(message: NonexistentModule)
  end

  test "subscribe and unsubscribe" do
    assert :ok = MAVLink.Router.subscribe(message: TestMavlink.Message.Heartbeat)
    assert :ok = MAVLink.Router.unsubscribe()
  end

  test "init without dialect fails" do
    pid =
      spawn(fn ->
        GenServer.start_link(
          MAVLink.Router,
          %{dialect: nil, system: 1, component: 1, connection_strings: []},
          []
        )
      end)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
  end

  test "pack_and_send returns ok for valid message" do
    MAVLink.Test.DialectFixture.ensure_compiled!()

    assert :ok =
             MAVLink.Router.pack_and_send(
               struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic])
             )
  end
end
