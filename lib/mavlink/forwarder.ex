defmodule MAVLink.Forwarder do
  @moduledoc false

  alias MAVLink.{RouteTable, WireConnection}

  def route(source_pid, source_connection_key, frame = %MAVLink.Frame{source_system: sys, source_component: comp}) do
    unless source_connection_key == :local do
      RouteTable.put_route({sys, comp}, {source_pid, source_connection_key})
    end

    wire_recipients =
      case frame.target do
        :broadcast ->
          RouteTable.all_wire_peers()
          |> Enum.reject(fn {pid, key} ->
            pid == source_pid and key == source_connection_key
          end)

        _ ->
          RouteTable.matching_peers(frame.target_system, frame.target_component)
          |> Enum.map(fn
            {pid, key} when is_pid(pid) -> {pid, key}
            pid when is_pid(pid) -> {pid, nil}
          end)
          |> Enum.uniq()
      end

    for {dest_pid, connection_key} <- wire_recipients do
      case WireConnection.wire_packet(frame) do
        nil ->
          send(dest_pid, {:mavlink_forward, frame, connection_key})

        packet ->
          send(dest_pid, {:mavlink_forward_raw, packet, connection_key})
      end
    end

    for {pid, delivery} <- RouteTable.matching_subscribers(frame) do
      send(pid, delivery)
    end

    :ok
  end
end
