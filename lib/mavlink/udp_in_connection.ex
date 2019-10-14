defmodule MAVLink.UDPInConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  require Logger
  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil]
  @type t :: %MAVLink.UDPInConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid}
             
             
  def handle_info({:udp, socket, source_addr, source_port, raw}, state) do
    receiving_connection = struct(MAVLink.UDPInConnection,
                          socket: socket, address: source_addr, port: source_port)
    case binary_to_frame_and_tail(raw) do
      :not_a_frame ->
        # Noise or malformed frame
        {:error, state}
      {received_frame, _rest} -> # UDP sends frame per packet, so ignore rest
        case validate_and_unpack(received_frame, state.dialect) do
          {:ok, valid_frame} ->
            {:ok, receiving_connection, valid_frame, state}
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            {:ok, receiving_connection, received_frame, state}
          reason ->
              Logger.warn(
                "UDP MAVLink frame received from " <>
                "#{Enum.join(Tuple.to_list(source_addr), ".")}:#{source_port} failed: #{Atom.to_string(reason)}")
              {:error, state}
        end
    end
  end
  
  
  def connect(["udpin", address, port], state) do
    {:ok, _} = :gen_udp.open(
      port,
      [:binary, ip: address, active: :true]
    )
    
    # Do not add UDP In to connections, we don't want to forward to ourselves
    state
  end
  
  
  # Do not forward to ourselves...
  def forward(%MAVLink.UDPInConnection{}, _, state), do: {:noreply, state}

end
