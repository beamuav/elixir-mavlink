defmodule MAVLink.Test.ConnectionStubs do
  @moduledoc false

  alias MAVLink.{UDPInConnection, UDPOutConnection, TCPOutConnection, SerialConnection}

  def udp_in(socket, ip \\ {127, 0, 0, 1}, port \\ 14_550) do
    %UDPInConnection{socket: socket, address: ip, port: port}
  end

  def udp_out(socket, ip \\ {127, 0, 0, 1}, port \\ 14_550) do
    %UDPOutConnection{socket: socket, address: ip, port: port}
  end

  def tcp_out(socket, ip \\ {127, 0, 0, 1}, port \\ 5760) do
    %TCPOutConnection{socket: socket, address: ip, port: port, buffer: <<>>}
  end

  def serial(port \\ "/dev/ttyTEST", baud \\ 57_600) do
    %SerialConnection{port: port, baud: baud, uart: nil, buffer: <<>>}
  end
end
