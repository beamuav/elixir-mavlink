defmodule MAVLink.Utils do
  @moduledoc ~s"""
  MAVLink support functions used during code generation and runtime
  Parts of this module are ported from corresponding implementations
  in mavutils.py
  """
  
  
  use Bitwise, only_operators: true
  
  
  import List, only: [flatten: 1]
  import Enum, only: [sort_by: 2, join: 2, map: 2, reverse: 1]
  
  
  @doc """
  Sort parsed message fields into wire order according
  to https://mavlink.io/en/guide/serialization.html
  List extension fields separately so that we can
  not include them for MAVLink 1 messages
  """
  @spec wire_order([%{type: String.t, is_extension: boolean}]) :: [[%{}]]
  def wire_order(fields) do
    type_order_map = %{
      uint64_t:                 1,
      int64_t:                  1,
      double:                   1,
      uint32_t:                 2,
      int32_t:                  2,
      float:                     2,
      uint16_t:                 3,
      int16_t:                  3,
      uint8_t:                  4,
      uint8_t_mavlink_version:  4,
      int8_t:                   4,
      char:                     4
    }
    [
      sort_by(
        Enum.filter(fields, & !&1.is_extension),
        &Map.fetch(type_order_map, String.to_atom(&1.type))
      ),
      Enum.filter(fields, & &1.is_extension)
    ]
  end
  
  
  def eight_bit_checksum(value) do
    (value &&& 0xFF) ^^^ (value >>> 8)
  end
  
  
  @doc """
  Calculate an x25 checksum of a list or binary based on
  pymavlink mavcrc.x25crc
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
    crc = (crc >>> 8) ^^^ (tmp <<< 8) ^^^ (tmp <<< 3) ^^^ (tmp >>> 4)
    crc &&& 0xffff
  end
  
  
  @doc "Helper function for messages to pack string fields"
  @spec pack_string(binary, non_neg_integer) :: binary
  def pack_string(s, ordinality) do
    s |> String.pad_trailing(ordinality, <<0>>)
  end
  
  
  @doc "Helper function for messages to pack array fields"
  @spec pack_array(list(), integer, (any() -> binary())) :: binary()
  def pack_array(a, ordinality, _) when length(a) > ordinality, do: {:error, "Maximum elements allowed is \#{ordinality}"}
  def pack_array(a, ordinality, field_packer) when length(a) < ordinality, do: pack_array(a ++ [0], ordinality, field_packer)
  def pack_array(a, _, field_packer), do: a |> map(field_packer) |> join(<<>>)
  
  
  @doc "Helper function for decode() to unpack array fields"
  # TODO bitstring generator instead? https://elixir-lang.org/getting-started/comprehensions.html
  @spec unpack_array(binary(), (binary()-> {any(), list()})) :: list()
  def unpack_array(bin, fun), do: unpack_array(bin, fun, [])
  def unpack_array(<<>>, _, lst), do: reverse(lst)
  def unpack_array(bin, fun, lst) do
    {elem, rest} = fun.(bin)
    unpack_array(rest, fun, [elem | lst])
  end
  
  
  @doc "Parse an ip address string into a tuple"
  def parse_ip_address(address) when is_binary(address) do
    parse_ip_address(String.split(address, "."), [], 0)
  end
  
  def parse_ip_address([], address, 4) do
    List.to_tuple(reverse address)
  end
  
  def parse_ip_address([], _, _) do
    {:error, :invalid_ip_address}
  end
  
  def parse_ip_address([component | rest], address, count) do
    case Integer.parse(component) do
      :error ->
        {:error, :invalid_ip_address}
      {n, _} ->
        cond do
          n >= 0 and n <= 255 ->
            parse_ip_address(rest, [n | address], count + 1)
          true ->
            {:error, :invalid_ip_address}
        end
    end
  end
  
  
  def parse_positive_integer(port) when is_binary(port) do
    case Integer.parse(port) do
      :error ->
        :error
      {n, _} when n > 0 ->
        n
      _ ->
        :error
    end
  end
  
  
  def pack_float(f) when is_float(f), do: <<f::little-signed-float-size(32)>>
  def pack_float(:nan), do: <<0, 0, 192, 127>> # Have received these from QGroundControl
  
  
  def unpack_float(<<f::little-signed-float-size(32)>>), do: f
  def unpack_float(<<0, 0, 192, 127>>), do: :nan
  
  
  def pack_double(f) when is_float(f), do: <<f::little-signed-float-size(64)>>
  def pack_double(:nan), do: <<0, 0, 0, 0, 0, 0, 248, 127>> # Quick test in C gave this for double NaN
  
  
  def unpack_double(<<f::little-signed-float-size(64)>>), do: f
  def unpack_double(<<0, 0, 0, 0, 0, 0, 248, 127>>), do: :nan
  

end
