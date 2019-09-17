defmodule MAVLink.UDPConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  require Logger
  import MAVLink.Router, only: [route: 1]
  import MAVLink.Frame, only: [validate_and_unpack: 2]
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil]
  @type t :: %MAVLink.UDPConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid}
             
             
  def handle_info({:udp, socket, source_addr, source_port}, raw, state) do
    receiving_connection = MAVLink.UDPConnection
                          |> struct(socket: socket, address: source_addr,
                               port: source_port)
    case unpack_frame(raw) do
      {received_frame, _} -> # UDP sends frame per packet, so ignore rest
        case validate_and_unpack(received_frame, state.dialect) do
          {:ok, valid_frame} ->
            route(
              receiving_connection,
              valid_frame,
              state
            )
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            route(
              receiving_connection,
              received_frame,
              state
            )
          reason ->
              Logger.warn(
                "UDP MAVLink frame received from " <>
                "#{source_addr}:#{source_port} failed: #{Atom.to_string(reason)}")
              state
        end
      <<>> ->
        # Noise or malformed frame
        state
    end
  end
  
  
  def connect(["udp", address, port],
                      state=%MAVLink.Router{connections: connections}) do
    {:ok, socket} = :gen_udp.open(port,
      [:binary, ip: address, active: :true])
    
    connection = MAVLink.UDPConnection
        |> struct(%{
          socket: socket,
          address: address,
          port: port})
    
    state |> struct([
      connections: Map.put(
        connections, connection, 1) # TODO x 10 to force connection to mavlink version
    ])

  end
  
  
  def forward(%MAVLink.UDPConnection{socket, address, port},
        frame, state) do
    # Mirror what we sent back through receive code to test
    handle_info({:udp, socket, address, port, frame}, state)
    {:noreply, state} #TODO really forward over UDP
  end

end
