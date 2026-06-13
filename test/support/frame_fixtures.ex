defmodule MAVLink.Test.FrameFixtures do
  @moduledoc false

  alias MAVLink.Frame

  def heartbeat_v2_raw(opts \\ []) do
    sys = Keyword.get(opts, :source_system, 1)
    comp = Keyword.get(opts, :source_component, 1)
    seq = Keyword.get(opts, :sequence_number, 0)

    %Frame{
      version: 2,
      message_id: 0,
      payload: <<0>>,
      crc_extra: 93,
      sequence_number: seq,
      source_system: sys,
      source_component: comp,
      target_system: 0,
      target_component: 0,
      target: :broadcast
    }
    |> Frame.pack_frame()
    |> Map.fetch!(:mavlink_2_raw)
  end

  def heartbeat_frame(opts \\ []) do
    sys = Keyword.get(opts, :source_system, 1)
    comp = Keyword.get(opts, :source_component, 1)
    seq = Keyword.get(opts, :sequence_number, 0)

    %Frame{
      version: 2,
      message_id: 0,
      payload: <<0>>,
      crc_extra: 93,
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
