defmodule Mavlink.Test.Parser do
  use ExUnit.Case
  import Mavlink.Parser

  @root_dir File.cwd!

  test "parse mavlink XML no such file" do
    assert {:error, :enoent} = parse_mavlink_xml("snark")
  end
  
  test "parse mini mavlink XML" do
    assert %{
              dialect: 0,
              enums: [
                %{
                  description: "Micro air vehicle / autopilot classes. This identifies the individual model.",
                  entries: [
                    %{
                      description: "Generic autopilot, full support for everything",
                      name: :mav_autopilot_generic,
                      params: [],
                      value: 0
                    }
                  ],
                  name: :mav_autopilot
                }
              ],
              messages: [
                %{
                  description: "The heartbeat message shows that a system is present and responding. The type of the MAV and Autopilot hardware allow the receiving system to treat further messages from this system appropriate (e.g. by laying out the user interface based on the autopilot).",
                  fields: [
                    %{
                      description: "Type of the MAV (quadrotor, helicopter, etc., up to 15 types, defined in MAV_TYPE ENUM)",
                      display: nil,
                      enum: :MAV_TYPE,
                      name: :type,
                      ordinality: 0,
                      type: :uint8,
                      units: nil
                    }
                  ],
                  id: 0,
                  name: :heartbeat
                }
              ],
              version: 3
            } = parse_mavlink_xml("#{@root_dir}/test/input/mini_mavlink.xml")
  end
  
end
