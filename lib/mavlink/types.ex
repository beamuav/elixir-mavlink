defmodule MAVLink.Types do
  @moduledoc """
  Core types that remain the same across dialects.
  """
  
  @typedoc "Connection delegate modules for MAVLink.Router"
  @type connection ::  MAVLink.SerialConnection | MAVLink.TCPConnection | MAVLink.UDPInConnection | MAVLink.UDPOutConnection
  
  @typedoc "A system/component id tuple"
  @type mavlink_address :: {0..255, 0..255}
  
  @typedoc "MAVLink protocol version"
  @type version :: 1 | 2
  
  @typedoc "MAVLink message sequence number"
  @type sequence_number :: 0..255
  
  @typedoc "A 4-tuple network address"
  @type net_address :: {0..255, 0..255, 0..255, 0..255}
  
  @typedoc "A non-reserved network port"
  @type net_port :: 1024..65535
  
  @typedoc "A parameter description"
  @type param_description :: {pos_integer, String.t}
  
  @typedoc "A list of parameter descriptions"
  @type param_description_list :: [ param_description ]
  
  @typedoc "Type used for field in encoded message"
  @type field_type :: int8_t | int16_t | int32_t | int64_t | uint8_t | uint16_t | uint32_t | uint64_t | char | float | double
  
  @typedoc "8-bit signed integer"
  @type int8_t :: -128..127
  
  @typedoc "16-bit signed integer"
  @type int16_t :: -32_768..32_767
  
  @typedoc "32-bit signed integer"
  @type int32_t :: -2_147_483_647..2_147_483_647
  
  @typedoc "64-bit signed integer"
  @type int64_t :: integer
  
  @typedoc "8-bit unsigned integer"
  @type uint8_t :: 0..255
  
  @typedoc "16-bit unsigned integer"
  @type uint16_t :: 0..65_535
  
  @typedoc "32-bit unsigned integer"
  @type uint32_t :: 0..4_294_967_295
  
  @typedoc "64-bit unsigned integer"
  @type uint64_t :: pos_integer
  
  @typedoc "64-bit signed float"
  @type double :: Float64
  
  @typedoc "1 -> not an array 2..255 -> an array"
  @type field_ordinality :: 1..255
  
  @typedoc "A MAVLink message id"
  @type message_id :: non_neg_integer
  
  @typedoc "A CRC_EXTRA checksum"
  @type crc_extra :: 0..255

end
