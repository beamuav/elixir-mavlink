defmodule MAVLink.Test.RouteTableTest do
  use ExUnit.Case, async: false

  alias MAVLink.RouteTable
  alias MAVLink.Test.DialectFixture
  import MAVLink.Test.FrameFixtures

  setup do
    stop_route_table()
    DialectFixture.ensure_compiled!()
    {:ok, _} = GenServer.start_link(RouteTable, [], name: RouteTable)
    on_exit(fn -> stop_route_table() end)
    :ok
  end

  defp stop_route_table do
    case Process.whereis(RouteTable) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  test "put_route and matching_peers" do
    pid = self()
    RouteTable.put_route({1, 1}, {pid, :wire_a})
    RouteTable.put_route({2, 3}, {pid, :wire_b})

    assert [{^pid, :wire_a}] = RouteTable.matching_peers(1, 1)
    assert [{^pid, :wire_b}] = RouteTable.matching_peers(2, 0)
    assert [] = RouteTable.matching_peers(9, 9)
  end

  test "register_wire lists wire peers" do
    RouteTable.register_wire(self(), :sock_a)
    RouteTable.register_wire(self(), :sock_b)

    keys =
      RouteTable.all_wire_peers()
      |> Enum.filter(fn {pid, _} -> pid == self() end)
      |> Enum.map(fn {_, key} -> key end)
      |> Enum.sort()

    assert keys == [:sock_a, :sock_b]
  end

  test "subscribe delivers matching subscriber" do
    subscriber = self()

    frame =
      heartbeat_frame(source_system: 5, source_component: 2)
      |> Map.put(:message, struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic]))

    :ok =
      RouteTable.subscribe(
        %{
          message: TestMavlink.Message.Heartbeat,
          source_system: 5,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false
        },
        subscriber
      )

    assert [{^subscriber, msg}] = RouteTable.matching_subscribers(frame)
    assert msg.__struct__ == TestMavlink.Message.Heartbeat
    assert :ets.lookup(:mavlink_subscriber_index, {5, TestMavlink.Message.Heartbeat}) != []
  end

  test "subscriber index narrows wildcard lookups" do
    subscriber = self()

    :ok =
      RouteTable.subscribe(
        %{
          message: TestMavlink.Message.VfrHud,
          source_system: 2,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false
        },
        subscriber
      )

    heartbeat =
      heartbeat_frame(source_system: 2)
      |> Map.put(:message, struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic]))

    vfr =
      vfr_hud_frame(source_system: 2)
      |> Map.put(:message, struct(TestMavlink.Message.VfrHud, [
        airspeed: 12.5,
        groundspeed: 11.0,
        heading: 180,
        throttle: 55,
        alt: 120.0,
        climb: 0.5
      ]))

    assert [] = RouteTable.matching_subscribers(heartbeat)
    assert [{^subscriber, msg}] = RouteTable.matching_subscribers(vfr)
    assert msg.__struct__ == TestMavlink.Message.VfrHud
  end

  test "unsubscribe removes subscriber on DOWN" do
    pid =
      spawn(fn ->
        RouteTable.subscribe(%{message: nil, source_system: 0, source_component: 0, target_system: 0, target_component: 0, as_frame: false}, self())
        receive do :stop -> :ok end
      end)

    Process.sleep(20)
    send(pid, :stop)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500
    Process.sleep(20)
    assert :ets.tab2list(:mavlink_subscribers) == []
    assert :ets.tab2list(:mavlink_subscriber_index) == []
  end
end
