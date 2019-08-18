defmodule MAVLink.UDPConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  
  import MAVLink.Router, only: [validate_and_route_message_frame: 12]
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil,
    received: 0,
    dropped: 0
  ]
  @type t :: %MAVLink.UDPConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid,
               received: non_neg_integer,
               dropped: non_neg_integer
             }
  
  def handle_info({:udp, sock, source_addr, source_port, raw=
    <<0xfe, # MAVLink version 1
      payload_length::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system_id::unsigned-integer-size(8),
      source_component_id::unsigned-integer-size(8),
      message_id::unsigned-integer-size(8),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do

    {
      :noreply,
      state |> validate_and_route_message_frame(
                 sock, {source_addr, source_port},
                 1, sequence_number, source_system_id, source_component_id,
                 message_id, payload_length, payload, checksum, raw)
    }
  end
  
  def handle_info({:udp, sock, source_addr, source_port, raw=
    <<0xfd, # MAVLink version 2
      payload_length::unsigned-integer-size(8),
      0::unsigned-integer-size(8),   # TODO Rejecting all incompatible flags for now
      _compatible_flags::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system_id::unsigned-integer-size(8),
      source_component_id::unsigned-integer-size(8),
      message_id::little-unsigned-integer-size(24),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do
    
    {
      :noreply,
      state |> validate_and_route_message_frame(
                 sock, {source_addr, source_port},
                 2, sequence_number, source_system_id, source_component_id,
                 message_id, payload_length, payload, checksum, raw)
    }
  end
  
  def handle_info({:udp, _sock, _addr, _port, _}, state) do
    # Ignore UDP packets we don't recognise
    {:noreply, state}
  end
  
  def connect(["udp", address, port], state) do
    {:ok, socket} = :gen_udp.open(port, [:binary, ip: address, active: :true])
    %MAVLink.Router{
      state | connections:
      put_in(
        state.connections,
        [socket],
        struct(
          MAVLink.UDPConnection,
          %{address: address, port: port, socket: socket}))}
  end
  

end
