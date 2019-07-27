defmodule Mavlink.Utils do
  @moduledoc ~s"""
  Mavlink support functions used during code generation and runtime
  Parts of this module are ported from corresponding implementations
  in mavutils.py
  """
  
  
  use Bitwise, only_operators: true
  
  
  import List, only: [flatten: 1]
  import Enum, only: [sort_by: 2, reduce: 3, join: 2, map: 2, reverse: 1]
  
  
  @doc """
  Sort parsed message fields into wire order according
  to https://mavlink.io/en/guide/serialization.html
  """
  @spec wire_order([ ]) :: [ ]
  def wire_order(fields) do
    type_order_map = %{
      uint64_t:                 1,
      int64_t:                  1,
      double:                   1,
      uint32_t:                 2,
      int32_t:                  2,
      float:                    2,
      uint16_t:                 3,
      int16_t:                  3,
      uint8_t:                  4,
      uint8_t_mavlink_version:  4,
      int8_t:                   4,
      char:                     4
    }
    
    sort_by(fields, &Map.fetch(type_order_map, String.to_atom(&1.type)))
    
  end
  
  
  @doc """
  Calculate an x25 checksum of a list or binary based on
  pymavlink mavcrc.x25crc
  """
  
  
  def eight_bit_checksum(value) do
    (value &&& 0xFF) ^^^ (value >>> 8)
  end
  
  
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
    crc = (crc >>> 8) ^^^ (tmp <<< 8) ^^^ (tmp <<< 3) ^^^ (tmp >>> 4)
    crc &&& 0xffff
  end
  
  
  @doc "Helper function for messages to pack bitmask fields"
  @spec pack_bitmask(MapSet.t(Mavlink.Types.enum_value), Mavlink.Types.enum_type, (Mavlink.Types.enum_value, Mavlink.Types.enum_type -> integer)) :: integer
  def pack_bitmask(flag_set, enum, encode), do: reduce(flag_set, 0, & &2 ^^^ encode.(&1, enum))
  
  
  @doc "Helper function for messages to pack string fields"
  @spec pack_string(String.t, integer) :: binary()
  def pack_string(s, ordinality) do
    s |> String.pad_trailing(ordinality - byte_size(s), <<0>>)
  end
  
  
  @doc "Helper function for messages to pack array fields"
  @spec pack_array(list(), integer, (any() -> binary())) :: binary()
  def pack_array(a, ordinality, _) when length(a) > ordinality, do: {:error, "Maximum elements allowed is \#{ordinality}"}
  def pack_array(a, ordinality, field_packer) when length(a) < ordinality, do: pack_array(a ++ [0], ordinality, field_packer)
  def pack_array(a, _, field_packer), do: a |> map(field_packer) |> join(<<>>)
  
  
  @doc "Helper function for decode() to unpack array fields"
  @spec unpack_array(binary(), (binary()-> {any(), list()})) :: list()
  def unpack_array(bin, fun), do: unpack_array(bin, fun, [])
  def unpack_array(<<>>, _, lst), do: reverse(lst)
  def unpack_array(bin, fun, lst) do
    {elem, rest} = fun.(bin)
    unpack_array(rest, fun, [elem | lst])
  end
  
  
  @doc "Helper function for decode() to unpack bitmask fields"
  @spec unpack_bitmask(integer, Mavlink.Types.enum_type, (integer, Mavlink.Types.enum_type -> Mavlink.Types.enum_value), MapSet.t, integer) :: MapSet.t(Mavlink.Types.enum_value)
  def unpack_bitmask(value, enum, decode, acc \\ MapSet.new(), pos \\ 1) do
    case {decode.(pos, enum), (value &&& pos) != 0} do
      {not_atom, _} when not is_atom(not_atom) ->
        acc
      {entry, true} ->
        unpack_bitmask(value, enum, decode, MapSet.put(acc, entry), pos <<< 1)
      {_, false} ->
        unpack_bitmask(value, enum, decode, acc, pos <<< 1)
    end
  end

end
