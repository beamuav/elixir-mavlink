defmodule MAVLink.UDPConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  require Logger
  import MAVLink.Frame, only: [unpack_frame: 1, validate_and_unpack: 2]
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil]
  @type t :: %MAVLink.UDPConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid}
             
             
  def handle_info({:udp, socket, source_addr, source_port, raw}, state) do
    receiving_connection = MAVLink.UDPConnection
                          |> struct(socket: socket, address: source_addr,
                               port: source_port)
    case unpack_frame(raw) do
      {received_frame, _} -> # UDP sends frame per packet, so ignore rest
        case validate_and_unpack(received_frame, state.dialect) do
          {:ok, valid_frame} ->
            {:ok, receiving_connection, valid_frame, state}
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            {:ok, receiving_connection, received_frame, state}
          reason ->
              Logger.warn(
                "UDP MAVLink frame received from " <>
                "#{source_addr}:#{source_port} failed: #{Atom.to_string(reason)}")
              {:error, state}
        end
      _ ->
        # Noise or malformed frame
        {:error, state}
    end
  end
  
  
  def connect(["udp", address, port],
                      state=%MAVLink.Router{connections: connections}) do
    {:ok, socket} = :gen_udp.open(
      port,
      [:binary, ip: address, active: :true]
    )
    
    struct(
      state,
      [
        connections: MapSet.put(
          connections,
          struct(
            MAVLink.UDPConnection,
            [socket: socket, address: address, port: port]
          )
        )
      ]
    )

  end
  
  
  def forward(%MAVLink.UDPConnection{
      socket: _socket,
      address: _address,
      port: _port}, _frame, state) do
    #TODO really forward over UDP
    {:noreply, state}
  end

end
