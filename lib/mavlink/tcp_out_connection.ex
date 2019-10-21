defmodule MAVLink.TCPOutConnection do
  @moduledoc """
  MAVLink.Router delegate for TCP connections
  Typically used to connect to SITL on port 5760
  """
  
  @smallest_mavlink_message 8
  
  require Logger
  alias MAVLink.Frame
  
  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]
  
  
  defstruct [socket: nil, buffer: <<>>]
  @type t :: %MAVLink.TCPOutConnection{socket: pid, buffer: binary}
  
  
  def handle_info({:tcp, socket, raw}, receiving_connection=%MAVLink.TCPOutConnection{buffer: buffer}, dialect) do
    case binary_to_frame_and_tail(buffer <> raw) do
      :not_a_frame ->
        # Noise or malformed frame
        Logger.warn("TCPOutConnection.handle_info: Not a frame #{inspect(raw)}")
        {:error, :not_a_frame, socket, struct(receiving_connection, [buffer: <<>>])}
      {nil, rest} ->
        {:error, :incomplete_frame, socket, struct(receiving_connection, [buffer: rest])}
      {received_frame, rest} ->
        # Rest could be a message, return later to try emptying the buffer
        if byte_size(rest) >= @smallest_mavlink_message, do: send self(), {:tcp, socket, <<>>}
        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, socket, struct(receiving_connection, [buffer: rest]), valid_frame}
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            Logger.warn "rebroadcasting unknown message with id #{received_frame.message_id}}"
            {:ok, socket, struct(receiving_connection, [buffer: rest]), struct(received_frame, [target: :broadcast])}
          reason ->
              Logger.warn(
                "TCPOutConnection.handle_info: frame received failed: #{Atom.to_string(reason)}")
              {:error, reason, socket, struct(receiving_connection, [buffer: rest])}
        end
    end
  end
  
  
  def connect(["tcpout", address, port], state=%MAVLink.Router{connections: connections}) do
    {:ok, socket} = :gen_tcp.connect(
      address,
      port,
      [:binary, active: :true]
    )
    
    struct(
      state,
      [
        connections: Map.put(
          connections,
          socket,
          struct(
            MAVLink.TCPOutConnection,
            [socket: socket]
          )
        )
      ]
    )

  end
  
  
  def forward(%MAVLink.TCPOutConnection{socket: socket},
      %Frame{version: 1, mavlink_1_raw: packet}) do
    :gen_udp.send(socket, packet)
  end
  
  def forward(%MAVLink.TCPOutConnection{socket: socket},
      %Frame{version: 2, mavlink_2_raw: packet}) do
    :gen_udp.send(socket, packet)
  end

end
