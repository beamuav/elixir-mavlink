defmodule Mavlink.Test.Parser do
  use ExUnit.Case
  import Mavlink.Parser

  
  @root_dir File.cwd!

  
  test "parse mavlink XML no such file" do
    assert {:error, "File 'snark' does not exist"} = parse_mavlink_xml("snark")
  end
  
  
  test "parse mini mavlink XML" do
    assert %{
              dialect: "0",
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
                      enum: "mav_type",
                      name: "type",
                      ordinality: 1,
                      type: "uint8_t",
                      units: nil
                    }
                  ],
                  id: 0,
                  name: "HEARTBEAT"
                }
              ],
              version: "3"
            } = parse_mavlink_xml("#{@root_dir}/test/input/mini_mavlink.xml")
  end
  
  
  test "extension fields identified" do
    assert  %{
              dialect: "0",
              enums: [],
              messages: [
                %{
                  description: "Optical flow from a flow sensor (e.g. optical mouse sensor)",
                  fields: [
                    %{
                      constant_val: nil,
                      description: "Optical flow quality / confidence. 0: bad, 255: maximum quality",
                      display: nil,
                      enum: "",
                      is_extension: false,
                      name: "quality",
                      omit_arg: false,
                      ordinality: 1,
                      print_format: nil,
                      type: "uint8_t",
                      units: nil
                    },
                    %{
                      constant_val: nil,
                      description: "Ground distance in meters. Positive value: distance known. Negative value: Unknown distance",
                      display: nil,
                      enum: "",
                      is_extension: false,
                      name: "ground_distance",
                      omit_arg: false,
                      ordinality: 1,
                      print_format: nil,
                      type: "float",
                      units: :m
                    },
                    %{
                      constant_val: nil,
                      description: "Flow rate in radians/second about X axis",
                      display: nil,
                      enum: "",
                      is_extension: true,
                      name: "flow_rate_x",
                      omit_arg: false,
                      ordinality: 1,
                      print_format: nil,
                      type: "float",
                      units: :"rad/s"
                    },
                    %{
                      constant_val: nil,
                      description: "Flow rate in radians/second about Y axis",
                      display: nil,
                      enum: "",
                      is_extension: true,
                      name: "flow_rate_y",
                      omit_arg: false,
                      ordinality: 1,
                      print_format: nil,
                      type: "float",
                      units: :"rad/s"
                    }
                  ],
                  id: 100,
                  name: "OPTICAL_FLOW"
                }
              ],
              version: "2"
            } =  parse_mavlink_xml("#{@root_dir}/test/input/extensions.xml")
  end
  
  
  test "parse mini mavlink with include" do
    assert %{
      dialect: "0",
      enums: [
        %{
          description: "Micro air vehicle / autopilot classes.",
          entries: [
            %{
              description: "Generic autopilot, full support for everything",
              name: :mav_autopilot_generic,
              params: [],
              value: 0
            },
            %{
              description: "An autopilot entry included from an include file",
              name: :mav_autopilot_included,
              params: [],
              value: 1
            }
          ],
          name: :mav_autopilot
        }
      ],
      messages: [
        %{
          description: "The heartbeat message shows that a system is present and responding.",
          fields: [
            %{
              constant_val: nil,
              description: "Type of the MAV",
              display: nil,
              enum: "mav_type",
              is_extension: false,
              name: "type",
              omit_arg: false,
              ordinality: 1,
              print_format: nil,
              type: "uint8_t",
              units: nil
            }
          ],
          has_ext_fields: false,
          id: 0,
          name: "HEARTBEAT"
        },
        %{
          description: "A heartbeat message included from an include file",
          fields: [
            %{
              constant_val: nil,
              description: "A field included from an include file",
              display: nil,
              enum: "mav_type",
              is_extension: false,
              name: "type",
              omit_arg: false,
              ordinality: 1,
              print_format: nil,
              type: "uint8_t",
              units: nil
            }
          ],
          has_ext_fields: false,
          id: 100000,
          name: "HEARTBEAT_INCLUDED"
         }
      ],
      version: "3"
    } = parse_mavlink_xml("#{@root_dir}/test/input/mini_mavlink_include.xml")
  end

  
end
