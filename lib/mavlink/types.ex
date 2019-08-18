defmodule MAVLink.Types do
  @moduledoc """
  Core types that remain the same across dialects.
  """
  
  @type connection ::  MAVLink.SerialConnection | MAVLink.TCPConnection | MAVLink.UDPConnection
  @type mavlink_address :: {non_neg_integer, non_neg_integer}
  @type net_address :: {0..255, 0..255, 0..255, 0..255}
  @type net_port :: {1024..65535}

end
