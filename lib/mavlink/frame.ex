defmodule MAVLink.Frame do
  @moduledoc """
  Represent and work with MAVLink v1/2 message frames
  """
  
  
  require Logger
  
  
  defstruct [
    version: 2,
    payload_length: nil,
    incompatible_flags: 0,      # MAVLink 2 only
    compatible_flags: 0,        # MAVLink 2 only
    sequence_number: nil,
    source_system: nil,
    source_component: nil,
    target_system: nil,
    target_component: nil,
    message_id: nil,
    crc_extra: nil,
    payload: nil,
    checksum: nil,
    signature: nil,             # MAVLink 2 signing only (not implemented)
    mavlink_1_raw: nil,         # Original binary frame
    mavlink_2_raw: nil,
    message: nil
  ]
  @type message :: MAVLink.Pack.t
  @type t :: %MAVLink.Frame{
                version: 1 | 2,
                payload_length: 1..255,
                incompatible_flags: non_neg_integer,
                compatible_flags: non_neg_integer,
                sequence_number: 0..255,
                source_system: 1..255,
                source_component: 1..255,
                target_system: 1..255,
                target_component: 1..255,
                message_id: MAVLink.Types.message_id,
                crc_extra: MAVLink.Types.crc_extra,
                payload: binary,
                checksum: pos_integer,
                mavlink_1_raw: binary,
                mavlink_2_raw: binary,
                message: message
             }
             
 
  @spec unpack_frame(binary) :: {MAVLink.Frame.t, binary} | binary
  def unpack_frame(raw_and_rest=<<0xfe, # MAVLink version 1
      payload_length::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system::unsigned-integer-size(8),
      source_component::unsigned-integer-size(8),
      message_id::unsigned-integer-size(8),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16),
      rest::binary>>) do
    {
      MAVLink.Frame |> struct([
        version: 1,
        payload_length: payload_length,
        sequence_number: sequence_number,
        source_system: source_system,
        source_component: source_component,
        message_id: message_id,
        payload: payload,
        checksum: checksum,
        mavlink_1_raw: binary_part(
          raw_and_rest,
          0,
          byte_size(raw_and_rest) - byte_size(rest))
      ]),
      rest
    }
  end
  
  def unpack_frame(raw_and_rest=<<0xfd, # MAVLink version 2
      payload_length::unsigned-integer-size(8),
      0::unsigned-integer-size(8),
      compatible_flags::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system::unsigned-integer-size(8),
      source_component::unsigned-integer-size(8),
      message_id::little-unsigned-integer-size(24),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16),
      rest::binary>>) do
    {
      MAVLink.Frame |> struct([
        version: 2,
        payload_length: payload_length,
        incompatible_flags: 0,                # TODO handle incompatible flags
        compatible_flags: compatible_flags,
        sequence_number: sequence_number,
        source_system: source_system,
        source_component: source_component,
        message_id: message_id,
        payload: payload,
        checksum: checksum,
        mavlink_2_raw: binary_part(
          raw_and_rest,
          0,
          byte_size(raw_and_rest) - byte_size(rest))
      ]),
      rest
    }
  end
                           
  def unpack_frame(<<_, rest::binary>>), do: unpack_frame(rest)
  def unpack_frame(<<>>), do: <<>>
  
  
  # TODO MAVLink.Dialect protocol to replace "module", change MAVLink.Pack to MAVLink.Message?
  @spec validate_and_unpack(MAVLink.Frame, module) :: {:ok, MAVLink.Frame} | :failed_to_unpack | :checksum_invalid | :unknown_message
  def validate_and_unpack(frame, dialect) do
    case apply(dialect, :msg_attributes, [frame.message_id]) do
      {:ok, crc_extra, expected_length, targeted?} ->
        if checksum == (
               :binary.bin_to_list(
                  elem({nil, frame.mavlink_1_raw, frame.mavlink_2_raw}, frame.version),
                  {1, frame.payload_length + elem({nil, 5, 9}, frame.version)})
                |> x25_crc()
                |> x25_crc([crc])) do
          payload_truncated_length = 8 * (expected_length - frame.payload_length)
          case apply(dialect, :unpack, [
            message_id,
            payload <> <<0::size(payload_truncated_length)>>]) do
            {:ok, message} ->
              if targeted? do
                frame |> struct([
                  message: message,
                  target_system: message.target_system,
                  target_component: message.target_component,
                  crc_extra: crc_extra
                ])
              else
                frame |> struct([
                  message: message,
                  target_system: 0,
                  target_component: 0,
                  crc_extra: crc_extra
                ])
              end
              
            _ ->
              :failed_to_unpack
          end
        else
          :checksum_invalid
        end
      _ ->
        :unknown_message
    end
  end
  
  
  # Pack version 1 and 2 message frames
  def pack_frame(frame) do
    payload_length = byte_size(frame.payload)
    mavlink_1_frame = <<frame.payload_length::unsigned-integer-size(8),
              frame.sequence_number::unsigned-integer-size(8),
              frame.source_system::unsigned-integer-size(8),
              frame.source_component::unsigned-integer-size(8),
              frame.message_id::little-unsigned-integer-size(8),
              frame.payload::binary()>>
    
    {truncated_length, truncated_payload} = truncate_payload(payload)
    mavlink_2_frame = <<truncated_length::unsigned-integer-size(8),
              0::unsigned-integer-size(8),  # Incompatible flags
              0::unsigned-integer-size(8),  # Compatible flags
              frame.sequence_number::unsigned-integer-size(8),
              frame.source_system::unsigned-integer-size(8),
              frame.source_component::unsigned-integer-size(8),
              frame.message_id::little-unsigned-integer-size(24),
              truncated_payload::binary()>>
    frame |> struct([
      mavlink_1_raw: <<0xfe>> <> mavlink_1_frame <> checksum(frame, crc_extra),
      mavlink_2_raw: <<0xfd>> <> mavlink_2_frame <> checksum(frame, crc_extra)
    ])
  end
  
  
  # MAVLink 2 truncate trailing 0s in payload
  defp truncate_payload(payload) do
    truncated_payload = String.replace_trailing(payload, <<0>>, "")
    if byte_size(truncated_payload) == 0 do
      {1, <<0>>}  # First byte of payload never truncated
    else
      {byte_size(truncated_payload), truncated_payload}
    end
  end
  
  
  # Calculate checksum
  defp checksum(frame, crc_extra) do
    cs = x25_crc(frame <> <<crc_extra::unsigned-integer-size(8)>>)
    <<cs::little-unsigned-integer-size(16)>>
  end
  
end
