defmodule Mavlink.Utils do
  @moduledoc ~s"""
  Mavlink support functions used during code generation and runtime
  Parts of this module are ported from corresponding implementations
  in mavutils.py
  """
  
  
  use Bitwise, only_operators: true
  
  
  import List, only: [flatten: 1]
  
  
  @doc """
  Calculate an x25 checksum of a list or binary
  """
  @spec x25_crc(List | Binary) :: pos_integer
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