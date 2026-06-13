defmodule MAVLink.Test.ForwarderTest do
  use ExUnit.Case, async: false

  alias MAVLink.{Forwarder, RouteTable}
  alias MAVLink.Test.DialectFixture
  import MAVLink.Test.FrameFixtures

  setup do
    stop_children()
    DialectFixture.ensure_compiled!()
    {:ok, _} = GenServer.start_link(RouteTable, [], name: RouteTable)
    on_exit(fn -> stop_children() end)
    :ok
  end

  defp stop_children do
    case Process.whereis(RouteTable) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  test "broadcast forwards to wire peers except source" do
    receiver = self()
    RouteTable.register_wire(receiver, :peer_a)
    RouteTable.register_wire(self(), :peer_b)

    frame = heartbeat_frame(target: :broadcast)
    :ok = Forwarder.route(self(), :peer_b, frame)

    assert_receive {:mavlink_forward, received, :peer_a}, 100
    assert received.message_id == frame.message_id
    refute_receive {:mavlink_forward, _, :peer_b}, 50
  end

  test "targeted route uses learned peer" do
    RouteTable.put_route({10, 20}, {self(), :dest})

    frame =
      heartbeat_frame(source_system: 1, source_component: 1)
      |> struct(target_system: 10, target_component: 20, target: :component)

    :ok = Forwarder.route(self(), :source, frame)
    assert_receive {:mavlink_forward, _, :dest}, 100
  end

  test "local source does not update routes" do
    frame = heartbeat_frame(source_system: 99, source_component: 88)
    :ok = Forwarder.route(self(), :local, frame)
    assert :ets.tab2list(:mavlink_routes) == []
  end

  test "matching subscribers receive directly" do
    subscriber = self()

    :ok =
      RouteTable.subscribe(
        %{
          message: TestMavlink.Message.Heartbeat,
          source_system: 0,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false
        },
        subscriber
      )

    :ok = Forwarder.route(self(), :wire, heartbeat_frame() |> Map.put(:message, struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic])))
    assert_receive msg, 100
    assert msg.__struct__ == TestMavlink.Message.Heartbeat
  end
end
