defmodule MAVLink.Frame do
  @moduledoc """
  Represent and work with MAVLink v1/2 message frames
  """
  
  
  require Logger
  
  import MAVLink.Utils, only: [x25_crc: 1, x25_crc: 2]
  
  
  defstruct [
    version: nil,              # Which raw attributes are populated?
    payload_length: nil,
    incompatible_flags: 0,      # MAVLink 2 only
    compatible_flags: 0,        # MAVLink 2 only
    sequence_number: nil,
    source_system: nil,
    source_component: nil,
    target_system: 0,          # Default to broadcast assumed elsewhere
    target_component: 0,
    target: nil,
    message_id: nil,
    crc_extra: nil,
    payload: nil,
    checksum: nil,
    signature: nil,             # MAVLink 2 signing only (not implemented)
    mavlink_1_raw: nil,         # Original binary frame
    mavlink_2_raw: nil,
    message: nil
  ]
  @type message :: MAVLink.Message.t
  @type version :: 1 | 2
  @type t :: %MAVLink.Frame{
                version: version,
                payload_length: 1..255,
                incompatible_flags: non_neg_integer,
                compatible_flags: non_neg_integer,
                sequence_number: 0..255,
                source_system: 1..255,
                source_component: 1..255,
                target_system: 1..255,
                target_component: 1..255,
                target: :broadcast | :system | :system_component | :component,
                message_id: MAVLink.Types.message_id,
                crc_extra: MAVLink.Types.crc_extra,
                payload: binary,
                checksum: pos_integer,
                mavlink_1_raw: binary,
                mavlink_2_raw: binary,
                message: message
             }
             
 
  @spec binary_to_frame_and_tail(binary) :: {MAVLink.Frame.t, binary} | {nil, binary} | :not_a_frame
  def binary_to_frame_and_tail(raw_and_rest=<<0xfe, # MAVLink version 1
      payload_length::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system::unsigned-integer-size(8),
      source_component::unsigned-integer-size(8),
      message_id::unsigned-integer-size(8),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16),
      rest::binary>>) do
    {
      struct(MAVLink.Frame, [
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
  
  def binary_to_frame_and_tail(raw_and_rest=<<0xfd, # MAVLink version 2
      payload_length::unsigned-integer-size(8),
      incompatible_flags::unsigned-integer-size(8),
      compatible_flags::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system::unsigned-integer-size(8),
      source_component::unsigned-integer-size(8),
      message_id::little-unsigned-integer-size(24),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16),
      rest::binary>>) do
    case incompatible_flags do
      0 ->
        # Vanilla MAVLink 2, we can deal with this
        {
          struct(MAVLink.Frame, [
            version: 2,
            payload_length: payload_length,
            incompatible_flags: 0,
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
      _ ->
        # We don't support any incompatible flags at present
        # e.g. signing, so drop the frame
        {nil, rest}
    end
  end
  
  def binary_to_frame_and_tail(unfinished_mavlink_1_frame=<<0xfe, _::binary>>), do: {nil, unfinished_mavlink_1_frame}
  def binary_to_frame_and_tail(unfinished_mavlink_2_frame=<<0xfd, _::binary>>), do: {nil, unfinished_mavlink_2_frame}
  def binary_to_frame_and_tail(<<_, rest::binary>>), do: binary_to_frame_and_tail(rest)
  def binary_to_frame_and_tail(<<>>), do: :not_a_frame
  
  
  @spec validate_and_unpack(MAVLink.Frame.t, module) :: {:ok, MAVLink.Frame.t} | :failed_to_unpack | :checksum_invalid | :unknown_message
  def validate_and_unpack(frame=%MAVLink.Frame{message_id: message_id, version: version, payload: payload}, dialect) do
    case apply(dialect, :msg_attributes, [message_id]) do
      {:ok, crc_extra, expected_length, target} ->
        if frame.checksum == (:binary.bin_to_list(
                                %{1 => frame.mavlink_1_raw, 2 => frame.mavlink_2_raw}[frame.version],
                                {1, frame.payload_length + %{1 => 5, 2 => 9}[frame.version]})
                              |> x25_crc()
                              |> x25_crc([crc_extra])) do
          payload_truncated_length = 8 * (expected_length - frame.payload_length)  # Only used to undo MAVLink 2 payload truncation
          try do  # Too many ways for unpack to fail with dodgy messages...
            case apply(dialect, :unpack, [
              message_id,
              version,
              payload <> (if payload_truncated_length > 0 and version > 1, do: <<0::size(payload_truncated_length)>>, else: <<>>)]) do
              {:ok, message} ->
                case target do
                  :broadcast ->
                    {:ok, struct(frame, [
                      message: message,
                      target_system: 0,
                      target_component: 0,
                      target: target,
                      crc_extra: crc_extra
                    ])}
                  :system ->
                    {:ok, struct(frame, [
                      message: message,
                      target_system: message.target_system,
                      target_component: 0,
                      target: target,
                      crc_extra: crc_extra
                    ])}
                  :system_component ->
                    {:ok, struct(frame, [
                      message: message,
                      target_system: message.target_system,
                      target_component: message.target_component,
                      target: target,
                      crc_extra: crc_extra
                    ])}
                  :component ->
                    {:ok, struct(frame, [
                      message: message,
                      target_system: 0,
                      target_component: message.target_component,
                      target: target,
                      crc_extra: crc_extra
                    ])}
                end
              _ ->
                :failed_to_unpack
            end
          rescue
            _ ->
              :ok = Logger.debug("validate_and_unpack: Failed to unpack #{inspect(frame)}, couldn't match payload")
              :failed_to_unpack
          end
        else
          :ok = Logger.debug("validate_and_unpack: Checksum invalid #{inspect(frame)}")
          :checksum_invalid
        end
      _ ->
        :ok = Logger.debug("validate_and_unpack: Unknown message #{inspect(frame)}")
        :unknown_message
    end
  end
  
  
  # Pack message frame
  def pack_frame(frame=%MAVLink.Frame{version: 1}) do
    payload_length = byte_size(frame.payload)
    mavlink_1_frame = <<payload_length::unsigned-integer-size(8),
              frame.sequence_number::unsigned-integer-size(8),
              frame.source_system::unsigned-integer-size(8),
              frame.source_component::unsigned-integer-size(8),
              frame.message_id::little-unsigned-integer-size(8),
              frame.payload::binary()>>
    
    frame |> struct([
      mavlink_1_raw: <<0xfe>> <> mavlink_1_frame <> checksum(mavlink_1_frame, frame.crc_extra)
    ])
  end
  
  def pack_frame(frame=%MAVLink.Frame{version: 2}) do
    {truncated_length, truncated_payload} = truncate_payload(frame.payload)
    mavlink_2_frame = <<truncated_length::unsigned-integer-size(8),
              0::unsigned-integer-size(8),  # Incompatible flags
              0::unsigned-integer-size(8),  # Compatible flags
              frame.sequence_number::unsigned-integer-size(8),
              frame.source_system::unsigned-integer-size(8),
              frame.source_component::unsigned-integer-size(8),
              frame.message_id::little-unsigned-integer-size(24),
              truncated_payload::binary()>>
    struct(frame,[
      mavlink_2_raw: <<0xfd>> <> mavlink_2_frame <> checksum(mavlink_2_frame, frame.crc_extra)
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
