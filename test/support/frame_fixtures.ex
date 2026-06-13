defmodule MAVLink.Test.FrameFixtures do
  @moduledoc false

  alias MAVLink.Frame
  import MAVLink.Utils, only: [pack_float: 1]

  def heartbeat_v2_raw(opts \\ []) do
    pack_v2_raw(0, 93, 1, opts, <<0>>)
    |> Map.fetch!(:mavlink_2_raw)
  end

  def vfr_hud_v2_raw(opts \\ []) do
    heading = Keyword.get(opts, :heading, 180)
    throttle = Keyword.get(opts, :throttle, 55)

    payload =
      pack_float(Keyword.get(opts, :airspeed, 12.5)) <>
        pack_float(Keyword.get(opts, :groundspeed, 11.0)) <>
        pack_float(Keyword.get(opts, :alt, 120.0)) <>
        pack_float(Keyword.get(opts, :climb, 0.5)) <>
        <<heading::little-signed-integer-size(16), throttle::little-unsigned-integer-size(16)>>

    pack_v2_raw(74, 20, byte_size(payload), opts, payload)
    |> Map.fetch!(:mavlink_2_raw)
  end

  def data16_v2_raw(opts \\ []) do
    type = Keyword.get(opts, :type, 1)
    len = Keyword.get(opts, :len, 16)
    data = Keyword.get(opts, :data, :binary.copy(<<0xAB>>, 16))
    payload = <<type::unsigned-integer-size(8), len::unsigned-integer-size(8), data::binary>>

    pack_v2_raw(169, 234, byte_size(payload), opts, payload)
    |> Map.fetch!(:mavlink_2_raw)
  end

  @doc """
  One vehicle telemetry burst: HUD-heavy mix similar to a fixed-wing stream.
  """
  def vehicle_telemetry_burst(vehicle_id, opts \\ []) do
    base = [source_system: vehicle_id, source_component: Keyword.get(opts, :source_component, 1)]

    [
      vfr_hud_v2_raw(Keyword.merge(base, [sequence_number: 1])),
      vfr_hud_v2_raw(Keyword.merge(base, [sequence_number: 2])),
      vfr_hud_v2_raw(Keyword.merge(base, [sequence_number: 3])),
      heartbeat_v2_raw(Keyword.merge(base, [sequence_number: 4])),
      data16_v2_raw(Keyword.merge(base, [sequence_number: 5]))
    ]
  end

  def heartbeat_frame(opts \\ []) do
    pack_v2_raw(0, 93, 1, opts, <<0>>)
  end

  def vfr_hud_frame(opts \\ []) do
    heading = Keyword.get(opts, :heading, 180)
    throttle = Keyword.get(opts, :throttle, 55)

    payload =
      pack_float(Keyword.get(opts, :airspeed, 12.5)) <>
        pack_float(Keyword.get(opts, :groundspeed, 11.0)) <>
        pack_float(Keyword.get(opts, :alt, 120.0)) <>
        pack_float(Keyword.get(opts, :climb, 0.5)) <>
        <<heading::little-signed-integer-size(16), throttle::little-unsigned-integer-size(16)>>

    pack_v2_raw(74, 20, byte_size(payload), opts, payload)
  end

  defp pack_v2_raw(message_id, crc_extra, payload_len, opts, payload \\ <<0>>) do
    sys = Keyword.get(opts, :source_system, 1)
    comp = Keyword.get(opts, :source_component, 1)
    seq = Keyword.get(opts, :sequence_number, 0)

    %Frame{
      version: 2,
      message_id: message_id,
      payload: payload,
      payload_length: payload_len,
      crc_extra: crc_extra,
      sequence_number: seq,
      source_system: sys,
      source_component: comp,
      target_system: 0,
      target_component: 0,
      target: :broadcast
    }
    |> Frame.pack_frame()
  end
end
