defmodule MAVLink.Test.RouterRoutingTest do
  use MAVLink.Test.RouterCase, async: false

  test "route learned on UDP receive" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    ip = {127, 0, 0, 1}
    port = 14_550
    key = {socket, ip, port}
    add_connection(key, udp_in(socket, ip, port))

    send(MAVLink.Router, {:udp, socket, ip, port, heartbeat_v2_raw(source_system: 1, source_component: 1)})
    Process.sleep(50)

    assert router_state().routes[{1, 1}] == key
    :gen_udp.close(socket)
  end

  test "local source excluded from routes" do
    MAVLink.Test.DialectFixture.ensure_compiled!()

    assert :ok =
             MAVLink.Router.pack_and_send(
               struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic])
             )

    Process.sleep(50)
    assert router_state().routes == %{}
  end

  test "broadcast delivers to local subscriber" do
    {:ok, sock_a} = :gen_udp.open(0, [:binary, active: false])
    {:ok, sock_b} = :gen_udp.open(0, [:binary, active: false])
    ip = {127, 0, 0, 1}
    add_connection({sock_a, ip, 14_551}, udp_in(sock_a, ip, 14_551))
    add_connection({sock_b, ip, 14_552}, udp_out(sock_b, ip, 14_552))

    :ok = MAVLink.Router.subscribe(message: TestMavlink.Message.Heartbeat)

    send(MAVLink.Router, {:udp, sock_a, ip, 14_551, heartbeat_v2_raw()})
    assert_receive msg, 500
    assert msg.__struct__ == TestMavlink.Message.Heartbeat

    :gen_udp.close(sock_a)
    :gen_udp.close(sock_b)
  end

  test "targeted delivery learns route" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    ip = {127, 0, 0, 1}
    port = 14_550
    key = {socket, ip, port}
    add_connection(key, udp_out(socket, ip, port))

    send(MAVLink.Router, {:udp, socket, ip, port, heartbeat_v2_raw(source_system: 1, source_component: 1)})
    Process.sleep(50)

    assert router_state().routes[{1, 1}] == key
    :gen_udp.close(socket)
  end

  test "add_connection registers connection" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    add_connection(socket, udp_out(socket))
    assert Map.has_key?(router_state().connections, socket)
    :gen_udp.close(socket)
  end

  test "tcp_closed removes connection" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    add_connection(socket, tcp_out(socket))
    send(MAVLink.Router, {:tcp_closed, socket})
    Process.sleep(50)
    refute Map.has_key?(router_state().connections, socket)
    :gen_udp.close(socket)
  end
end
