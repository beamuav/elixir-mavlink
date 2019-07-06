defmodule Mavlink.Utils do
  @moduledoc ~s"""
  Mavlink support functions used during code generation and runtime
  Parts of this module are ported from corresponding implementations
  in mavutils.py
  """
  
  
  use Bitwise, only_operators: true
  
  
  import List, only: [flatten: 1]
  import Enum, only: [sort_by: 2]
  
  
  @doc """
  Sort parsed message fields into wire order according
  to https://mavlink.io/en/guide/serialization.html
  """
  @spec wire_order([ ]) :: [ ]
  def wire_order(fields) do
    type_order_map = %{
      uint64: 1,
      int64:  1,
      double: 1,
      uint32: 2,
      int32:  2,
      float:  2,
      uint16: 3,
      int16:  3,
      uint8:  4,
      int8:   4
    }
    
    sort_by(fields, &Map.fetch(type_order_map, &1))
    
  end
  
  
  @doc """
  Calculate an x25 checksum of a list or binary
  """
  @spec x25_crc([ ] | binary()) :: pos_integer
  def x25_crc(list) when is_list(list) do
    x25_crc(0xffff, flatten(list))
  end
  
  def x25_crc(bin) when is_binary(bin) do
    x25_crc(0xffff, bin)
  end
  
  def x25_crc(crc, []), do: crc
  
  def x25_crc(crc, <<>>), do: crc
  
  def x25_crc(crc, [head | tail]) do
    crc |> x25_accumulate(head) |> x25_crc(tail)
  end
  
  def x25_crc(crc, << head :: size(8), tail :: binary>>) do
    crc |> x25_accumulate(head) |> x25_crc(tail)
  end
  
  defp x25_accumulate(crc, value) do
    tmp = value ^^^ (crc &&& 0xff)
    tmp = (tmp ^^^ (tmp <<< 4)) &&& 0xff
    crc = (crc >>> 8) ^^^ (crc <<< 8) ^^^ (tmp <<< 3) ^^^ (tmp >>> 4)
    crc &&& 0xffff
  end
  
end
