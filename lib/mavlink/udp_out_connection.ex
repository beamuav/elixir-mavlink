defmodule MAVLink.UDPOutConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  require Logger
  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]
  alias MAVLink.Frame
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil]
  @type t :: %MAVLink.UDPOutConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid}
  
  # Create connection if this is the first time we've received on it
  def handle_info({:udp, socket, source_addr, source_port, raw}, nil, dialect) do
    handle_info(
      {:udp, socket, source_addr, source_port, raw},
      %MAVLink.UDPOutConnection{address: source_addr, port: source_port, socket: socket},
      dialect)
  end

  def handle_info({:udp, socket, source_addr, source_port, raw}, receiving_connection, dialect) do
    case binary_to_frame_and_tail(raw) do
      :not_a_frame ->
        # Noise or malformed frame
        :ok = Logger.debug("UDPOutConnection.handle_info: Not a frame #{inspect(raw)}")
        {:error, :not_a_frame, {socket, source_addr, source_port}, receiving_connection}
      {received_frame, _rest} -> # UDP sends frame per packet, so ignore rest
        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            # Include address and port in connection key because multiple
            # clients can connect to a UDP "in" port.
            {:ok, {socket, source_addr, source_port}, receiving_connection, valid_frame}
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            :ok = Logger.debug "relaying unknown message with id #{received_frame.message_id}}"
            {:ok, {socket, source_addr, source_port}, receiving_connection, struct(received_frame, [target: :broadcast])}
          reason ->
              :ok = Logger.debug(
                "UDPOutConnection.handle_info: frame received from " <>
                "#{Enum.join(Tuple.to_list(source_addr), ".")}:#{source_port} failed: #{Atom.to_string(reason)}")
              {:error, reason, {socket, source_addr, source_port}, receiving_connection}
        end
    end
  end
  
  
  def connect(["udpout", address, port], controlling_process) do
    case :gen_udp.open(0, [:binary, ip: address, active: :true]) do
      {:ok, socket} ->
        :ok = Logger.info("Opened udpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}")
        send(
          controlling_process,
          {
            :add_connection,
            socket,
            struct(
              MAVLink.UDPOutConnection,
              [socket: socket, address: address, port: port]
            )
          }
        )
        :gen_udp.controlling_process(socket, controlling_process)
      other ->
        :ok = Logger.debug("Could not open udpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}: #{inspect(other)}. Retrying in 1 second")
        :timer.sleep(1000)
        connect(["udpout", address, port], controlling_process)
    end
  end
  
  
  def forward(%MAVLink.UDPOutConnection{
      socket: socket, address: address, port: port},
      %Frame{version: 1, mavlink_1_raw: packet}) do
    :gen_udp.send(socket, address, port, packet)
  end
  
  def forward(%MAVLink.UDPOutConnection{
      socket: socket, address: address, port: port},
      %Frame{version: 2, mavlink_2_raw: packet}) do
    :gen_udp.send(socket, address, port, packet)
  end

end
