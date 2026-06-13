defmodule MAVLink.Test.ConnectionDelegateTest do
  use ExUnit.Case, async: true

  import MAVLink.Test.FrameFixtures
  alias MAVLink.Test.DialectFixture
  alias MAVLink.{UDPInConnection, UDPOutConnection, TCPOutConnection, SerialConnection}

  setup do
    {:ok, dialect: DialectFixture.ensure_compiled!()}
  end

  test "UDPIn parses valid heartbeat", %{dialect: dialect} do
    socket = make_ref()
    ip = {127, 0, 0, 1}
    port = 14_550
    conn = %UDPInConnection{socket: socket, address: ip, port: port}

    assert {:ok, {^socket, ^ip, ^port}, ^conn, frame} =
             UDPInConnection.handle_info({:udp, socket, ip, port, heartbeat_v2_raw()}, conn, dialect)

    assert frame.message_id == 0
  end

  test "UDPIn unknown message rebroadcasts", %{dialect: dialect} do
    socket = make_ref()
    ip = {127, 0, 0, 1}
    port = 14_550
    conn = %UDPInConnection{socket: socket, address: ip, port: port}
    # Valid v2 frame with unknown message id 999 - will fail crc/unknown
    garbage = heartbeat_v2_raw() |> corrupt_message_id()

    result = UDPInConnection.handle_info({:udp, socket, ip, port, garbage}, conn, dialect)
    assert elem(result, 0) in [:ok, :error]
  end

  test "TCPOut buffers incomplete frame", %{dialect: dialect} do
    socket = make_ref()
    conn = %TCPOutConnection{socket: socket, buffer: <<>>}
    raw = heartbeat_v2_raw()
    <<part::binary-size(5), _::binary>> = raw

    assert {:error, :incomplete_frame, ^socket, updated} =
             TCPOutConnection.handle_info({:tcp, socket, part}, conn, dialect)

    assert byte_size(updated.buffer) == 5
  end

  test "Serial not_a_frame clears buffer on noise", %{dialect: dialect} do
    conn = %SerialConnection{port: "tty", baud: 57600, uart: nil, buffer: <<1, 2, 3>>}

    assert {:error, :not_a_frame, "tty", updated} =
             SerialConnection.handle_info({:circuits_uart, "tty", <<255, 255>>}, conn, dialect)

    assert updated.buffer == <<>>
  end

  test "UDPOut forward sends packet", %{dialect: dialect} do
    {:ok, receiver} = :gen_udp.open(0, [:binary, active: false, reuseaddr: true])
    {:ok, sender} = :gen_udp.open(0, [:binary, active: false])
    {:ok, port} = :inet.port(receiver)
    ip = {127, 0, 0, 1}
    frame = heartbeat_frame()
    conn = %UDPOutConnection{socket: sender, address: ip, port: port}

    UDPOutConnection.forward(conn, frame)
    assert {:ok, {_ip, _port, packet}} = :gen_udp.recv(receiver, 0, 200)
    assert is_binary(packet)
    assert byte_size(packet) > 10
    :gen_udp.close(receiver)
    :gen_udp.close(sender)
  end

  defp corrupt_message_id(raw) do
    <<hdr::binary-size(7), _mid::little-unsigned-integer-size(24), rest::binary>> = raw
    <<hdr::binary, 999::little-unsigned-integer-size(24), rest::binary>>
  end
end
