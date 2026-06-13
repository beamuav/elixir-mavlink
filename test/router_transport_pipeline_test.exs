defmodule MAVLink.Test.RouterTransportPipelineTest do
  use MAVLink.Test.RouterCase, async: false

  alias MAVLink.Test.UDPLoopback

  test "UDPIn creates client on first message" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    ip = {10, 0, 0, 1}
    port = 9_001
    add_connection({socket, ip, port}, nil)

    send(MAVLink.Router, {:udp, socket, ip, port, heartbeat_v2_raw(source_system: 2, source_component: 1)})
    Process.sleep(50)

    assert Map.has_key?(router_state().connections, {socket, ip, port})
    :gen_udp.close(socket)
  end

  test "UDPIn valid heartbeat learns route and delivers to subscriber" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    ip = {10, 0, 0, 2}
    port = 9_002
    add_connection({socket, ip, port}, udp_in(socket, ip, port))

    subscriber = self()
    :ok = MAVLink.Router.subscribe(message: TestMavlink.Message.Heartbeat)

    send(MAVLink.Router, {:udp, socket, ip, port, heartbeat_v2_raw(source_system: 3, source_component: 1)})
    assert_receive msg, 500
    assert msg.__struct__ == TestMavlink.Message.Heartbeat
    assert route_for({3, 1}) == {socket, ip, port}
    :gen_udp.close(socket)
  end

  test "UDPOut inbound learns route" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    ip = {127, 0, 0, 1}
    port = 9_003
    add_connection(socket, udp_out(socket, ip, port))

    send(MAVLink.Router, {:udp, socket, ip, port, heartbeat_v2_raw(source_system: 4, source_component: 1)})
    Process.sleep(50)

    assert route_for({4, 1}) == {socket, ip, port}
    :gen_udp.close(socket)
  end

  test "UDPOut forward sends to configured address" do
    {ip, recv_port, receiver, sender, _} = UDPLoopback.open_pair()
    add_connection(sender, udp_out(sender, ip, recv_port))

    {:ok, in_socket} = :gen_udp.open(0, [:binary, active: false])
    in_ip = {127, 0, 0, 1}
    in_port = 9_004
    add_connection({in_socket, in_ip, in_port}, udp_in(in_socket, in_ip, in_port))

    send(MAVLink.Router, {:udp, in_socket, in_ip, in_port, heartbeat_v2_raw(source_system: 5, source_component: 1)})
    Process.sleep(50)

    packets = UDPLoopback.drain(receiver, 200)
    assert length(packets) >= 1

    :gen_udp.close(receiver)
    :gen_udp.close(sender)
    :gen_udp.close(in_socket)
  end

  test "TCPOut buffers incomplete frame then completes" do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    add_connection(socket, tcp_out(socket))
    raw = heartbeat_v2_raw()
    <<part::binary-size(div(byte_size(raw), 2)), rest::binary>> = raw

    send(MAVLink.Router, {:tcp, socket, part})
    Process.sleep(20)
    assert byte_size(router_state().connections[socket].buffer) > 0

    send(MAVLink.Router, {:tcp, socket, rest})
    Process.sleep(50)
    assert route_for({1, 1}) == socket
    :gen_udp.close(socket)
  end

  test "Serial incomplete frame retains buffer" do
    port = "/dev/ttyTEST"
    add_connection(port, serial(port))
    raw = heartbeat_v2_raw()
    <<part::binary-size(div(byte_size(raw), 2)), rest::binary>> = raw

    send(MAVLink.Router, {:circuits_uart, port, part})
    Process.sleep(20)
    assert byte_size(router_state().connections[port].buffer) > 0

    send(MAVLink.Router, {:circuits_uart, port, rest})
    Process.sleep(50)
    assert route_for({1, 1}) == port
  end

  test "pack_and_send routes through local pipeline" do
    {ip, recv_port, receiver, sender, _} = UDPLoopback.open_pair()
    add_connection(sender, udp_out(sender, ip, recv_port))

    assert :ok =
             MAVLink.Router.pack_and_send(
               struct(TestMavlink.Message.Heartbeat, [type: :mav_type_generic])
             )

    Process.sleep(100)
    assert length(UDPLoopback.drain(receiver, 200)) >= 1
    :gen_udp.close(receiver)
    :gen_udp.close(sender)
  end
end
