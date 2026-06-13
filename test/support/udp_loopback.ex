defmodule MAVLink.Test.UDPLoopback do
  @moduledoc false

  def open_pair do
    {:ok, receiver} = :gen_udp.open(0, [:binary, active: false, reuseaddr: true])
    {:ok, sender} = :gen_udp.open(0, [:binary, active: false])
    {:ok, recv_port} = :inet.port(receiver)
    {:ok, send_port} = :inet.port(sender)
    {{127, 0, 0, 1}, recv_port, receiver, sender, send_port}
  end

  def drain(socket, timeout \\ 100) do
    drain(socket, timeout, [])
  end

    defp drain(socket, timeout, acc) do
      case :gen_udp.recv(socket, 0, timeout) do
        {:ok, {_ip, _port, data}} -> drain(socket, timeout, [data | acc])
        {:error, :timeout} -> Enum.reverse(acc)
      end
    end
end
