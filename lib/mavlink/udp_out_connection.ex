defmodule MAVLink.UDPOutConnection do
  @moduledoc """
  MAVLink.Router delegate for UDP connections
  """
  
  require Logger
  alias MAVLink.Frame
  
  
  defstruct [
    address: nil,
    port: nil,
    socket: nil]
  @type t :: %MAVLink.UDPOutConnection{
               address: MAVLink.Types.net_address,
               port: MAVLink.Types.net_port,
               socket: pid}
  
  
  def connect(["udpout", address, port], state=%MAVLink.Router{connections: connections}) do
    {:ok, socket} = :gen_udp.open(
      port,
      [:binary, ip: address, active: :true]
    )
    
    struct(
      state,
      [
        connections: Map.put(
          connections,
          socket,
          struct(
            MAVLink.UDPOutConnection,
            [socket: socket, address: address, port: port]
          )
        )
      ]
    )

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
