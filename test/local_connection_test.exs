defmodule MAVLink.Test.LocalConnectionTest do
  use ExUnit.Case, async: false

  alias MAVLink.{Forwarder, LocalConnection, RouteTable}
  alias MAVLink.Test.DialectFixture
  import MAVLink.Test.FrameFixtures

  setup do
    stop_children()
    dialect = DialectFixture.ensure_compiled!()
    {:ok, _} = GenServer.start_link(RouteTable, [], name: RouteTable)
    {:ok, _} =
      GenServer.start_link(
        LocalConnection,
        %{system: 245, component: 250, dialect: dialect},
        name: LocalConnection
      )

    on_exit(fn -> stop_children() end)

    {:ok, dialect: dialect}
  end

  defp stop_children do
    for name <- [LocalConnection, RouteTable] do
      case Process.whereis(name) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5_000)
      end
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  test "subscribe and forward matching heartbeat", %{dialect: _dialect} do
    subscriber = self()

    :ok =
      RouteTable.subscribe(
        %{
          message: TestMavlink.Message.Heartbeat,
          source_system: 1,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false
        },
        subscriber
      )

    frame =
      heartbeat_frame(source_system: 1, source_component: 1)
      |> Map.put(:message, struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic]))

    :ok = Forwarder.route(self(), :test, frame)
    assert_receive msg, 100
    assert msg.__struct__ == TestMavlink.Message.Heartbeat
  end

  test "as_frame delivers frame struct" do
    subscriber = self()
    :ok = RouteTable.subscribe(%{message: nil, source_system: 0, source_component: 0, target_system: 0, target_component: 0, as_frame: true}, subscriber)
    frame = heartbeat_frame()
    :ok = Forwarder.route(self(), :test, frame)
    assert_receive %MAVLink.Frame{}, 100
  end

  test "sequence number increments on local handle_info" do
    lc = %LocalConnection{system: 245, component: 250, sequence_number: 10}
    frame = Map.drop(heartbeat_frame(), [:mavlink_1_raw, :mavlink_2_raw])

    assert {:ok, :local, updated, packed} = LocalConnection.handle_info({:local, frame}, lc, TestMavlink)
    assert updated.sequence_number == 11
    assert packed.sequence_number == 10
  end

  test "unsubscribe removes subscriber" do
    subscriber = self()
    :ok = RouteTable.subscribe(%{}, subscriber)
    :ok = RouteTable.unsubscribe(subscriber)
    assert :ets.tab2list(:mavlink_subscribers) == []
  end
end
