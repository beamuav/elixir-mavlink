defmodule MAVLink.WireConnection do
  @moduledoc false

  alias MAVLink.Forwarder

  def route_result({:ok, connection_key, connection, frame}, pid) do
    :ok = Forwarder.route(pid, connection_key, frame)
    connection
  end

  def route_result({:error, _reason, _connection_key, connection}, _pid) do
    connection
  end

  def wire_packet(%MAVLink.Frame{version: 2, mavlink_2_raw: packet}) when is_binary(packet),
    do: packet

  def wire_packet(%MAVLink.Frame{version: 1, mavlink_1_raw: packet}) when is_binary(packet),
    do: packet

  def wire_packet(_), do: nil
end
