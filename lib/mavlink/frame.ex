defmodule MAVLink.Frame do
  @moduledoc """
  Represent and work with MAVLink v1/2 message frames
  """

  require Logger
  import MAVLink.Utils, only: [x25_crc: 1, x25_crc: 2]

  defstruct version: 2,
            payload_length: nil,
            # MAVLink 2 only
            incompatible_flags: 0,
            # MAVLink 2 only
            compatible_flags: 0,
            sequence_number: nil,
            source_system_id: nil,
            source_component_id: nil,
            message_id: nil,
            payload: nil,
            checksum: nil,
            # MAVLink 2 signing only (not implemented)
            signature: nil,
            # Original binary frame
            raw: nil

  @type t :: %MAVLink.Frame{
          version: 1 | 2,
          payload_length: 1..255,
          incompatible_flags: non_neg_integer,
          compatible_flags: non_neg_integer,
          sequence_number: 0..255,
          source_system_id: 1..255,
          source_component_id: 1..255,
          message_id: non_neg_integer,
          payload: binary,
          checksum: pos_integer,
          raw: binary
        }

  @spec from_binary(binary) :: {MAVLink.Frame.t(), binary} | binary
  # MAVLink version 1
  def from_binary(
        raw_and_rest =
          <<0xFE, payload_length::unsigned-integer-size(8),
            sequence_number::unsigned-integer-size(8), source_system_id::unsigned-integer-size(8),
            source_component_id::unsigned-integer-size(8), message_id::unsigned-integer-size(8),
            payload::binary-size(payload_length), checksum::little-unsigned-integer-size(16),
            rest::binary>>
      ) do
    {
      %MAVLink.Frame{
        version: 1,
        payload_length: payload_length,
        sequence_number: sequence_number,
        source_system_id: source_system_id,
        source_component_id: source_component_id,
        message_id: message_id,
        payload: payload,
        checksum: checksum,
        raw:
          binary_part(
            raw_and_rest,
            0,
            byte_size(raw_and_rest) - byte_size(rest)
          )
      },
      rest
    }
  end

  # MAVLink version 2
  def from_binary(
        raw_and_rest =
          <<0xFD, payload_length::unsigned-integer-size(8), 0::unsigned-integer-size(8),
            compatible_flags::unsigned-integer-size(8), sequence_number::unsigned-integer-size(8),
            source_system_id::unsigned-integer-size(8),
            source_component_id::unsigned-integer-size(8),
            message_id::little-unsigned-integer-size(24), payload::binary-size(payload_length),
            checksum::little-unsigned-integer-size(16), rest::binary>>
      ) do
    {
      %MAVLink.Frame{
        version: 2,
        payload_length: payload_length,
        # TODO handle incompatible flags
        incompatible_flags: 0,
        compatible_flags: compatible_flags,
        sequence_number: sequence_number,
        source_system_id: source_system_id,
        source_component_id: source_component_id,
        message_id: message_id,
        payload: payload,
        checksum: checksum,
        raw:
          binary_part(
            raw_and_rest,
            0,
            byte_size(raw_and_rest) - byte_size(rest)
          )
      },
      rest
    }
  end

  def from_binary(<<_, rest::binary>>), do: from_binary(rest)
  def from_binary(<<>>), do: <<>>

  # TODO MAVLink.Dialect protocol to replace "module", change MAVLink.Pack to MAVLink.Message?
  @spec validate(MAVLink.Frame, module) ::
          {:ok, MAVLink.Pack.t()} | :failed_to_unpack | :checksum_invalid | :unknown_message
  def validate(
        frame = %MAVLink.Frame{
          version: 1,
          payload_length: payload_length,
          sequence_number: sequence_number,
          source_system_id: source_system_id,
          source_component_id: source_component_id,
          message_id: message_id,
          payload: payload,
          checksum: checksum,
          raw: raw
        },
        dialect
      ) do
    case apply(dialect, :msg_attributes, [message_id]) do
      {:ok, crc, expected_length, targeted?} ->
        if checksum ==
             :binary.bin_to_list(
               frame.raw,
               {1, frame.payload_length + elem({0, 5, 9}, frame.version)}
             )
             |> x25_crc()
             |> x25_crc([crc]) do
          payload_truncated_length = 8 * (expected_length - frame.payload_length)

          case apply(dialect, :unpack, [
                 message_id,
                 payload <> <<0::size(payload_truncated_length)>>
               ]) do
            {:ok, message} ->
              {:ok, message}

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
end
