defmodule MAVLink.TCPConnection do
  @moduledoc """
  MAVLink.Router delegate for TCP connections
  """
  
  def connect(["tcp", _address, _port], state) do
    # TODO
    state
  end
  
  
  def handle_info({:tcp, _sock, _addr, _port, _}, state) do
    # TODO
    {:noreply, state}
  end
  

end
