defmodule MAVLink.Test.Parser do
  use ExUnit.Case
  import MAVLink.Parser
  
  
  @root_dir File.cwd!
  
  
  test "parse mavlink XML no such file" do
    assert {:error, "File 'snark' does not exist"} = parse_mavlink_xml("snark")
  end
  
  
  test "parse mini mavlink XML" do
    assert %{
             dialect: "0",
             enums: [
               %{
                 description: "MAVLINK component type reported in HEARTBEAT message. Flight controllers must report the type of the vehicle on which they are mounted (e.g. MAV_TYPE_OCTOROTOR). All other components must report a value appropriate for their type (e.g. a camera must use MAV_TYPE_CAMERA).",
                 entries: [
                   %{
                     description: "Generic micro air vehicle",
                     name: :mav_type_generic,
                     params: [],
                     value: 0
                   }
                 ],
                 name: :mav_type
               },
               %{
                 description: "Commands to be executed by the MAV. They can be executed on user request, or as part of a mission script. If the action is used in a mission, the parameter mapping to the waypoint/mission message is as follows: Param 1, Param 2, Param 3, Param 4, X: Param 5, Y:Param 6, Z:Param 7. This command list is similar what ARINC 424 is for commercial aircraft: A data format how to interpret waypoint/mission data. See https://mavlink.io/en/guide/xml_schema.html#MAV_CMD for information about the structure of the MAV_CMD entries",
                 entries: [
                   %{
                     description: "Navigate to waypoint.",
                     name: :mav_cmd_nav_waypoint,
                     params: [
                       %{
                         description: "Hold time. (ignored by fixed wing, time to stay at waypoint for rotary wing)",
                         index: 1
                       },
                       %{
                         description: "Acceptance radius (if the sphere with this radius is hit, the waypoint counts as reached)",
                         index: 2
                       },
                       %{
                         description: "0 to pass through the WP, if > 0 radius to pass by WP. Positive value for clockwise orbit, negative value for counter-clockwise orbit. Allows trajectory control.",
                         index: 3
                       },
                       %{
                         description: "Desired yaw angle at waypoint (rotary wing). NaN for unchanged.",
                         index: 4
                       },
                       %{description: "Latitude", index: 5},
                       %{description: "Longitude", index: 6},
                       %{description: "Altitude", index: 7}
                     ],
                     value: 16
                   }
                 ],
                 name: :mav_cmd
               }
             ],
             messages: [
               %{
                 description: "The heartbeat message shows that a system is present and responding. The type of the MAV and Autopilot hardware allow the receiving system to treat further messages from this system appropriate (e.g. by laying out the user interface based on the autopilot).",
                 fields: [
                   %{
                     constant_val: nil,
                     description: "Type of the MAV (quadrotor, helicopter, etc., up to 15 types, defined in MAV_TYPE ENUM)",
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
                 description: "Request to control this MAV",
                 fields: [
                   %{
                     constant_val: nil,
                     description: "System the GCS requests control for",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "target_system",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint8_t",
                     units: nil
                   },
                   %{
                     constant_val: nil,
                     description: "0: request control of this MAV, 1: Release control of this MAV",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "control_request",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint8_t",
                     units: nil
                   },
                   %{
                     constant_val: nil,
                     description: "0: key as plaintext, 1-255: future, different hashing/encryption variants. The GCS should in general use the safest mode possible initially and then gradually move down the encryption level if it gets a NACK message indicating an encryption mismatch.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "version",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint8_t",
                     units: :rad
                   },
                   %{
                     constant_val: nil,
                     description: "Password / Key, depending on version plaintext or encrypted. 25 or less characters, NULL terminated. The characters may involve A-Z, a-z, 0-9, and \"!?,.-\"",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "passkey",
                     omit_arg: false,
                     ordinality: 25,
                     print_format: nil,
                     type: "char",
                     units: nil
                   }
                 ],
                 has_ext_fields: false,
                 id: 5,
                 name: "CHANGE_OPERATOR_CONTROL"
               },
               %{
                 description: "Metrics typically displayed on a HUD for fixed wing aircraft.",
                 fields: [
                   %{
                     constant_val: nil,
                     description: "Current indicated airspeed (IAS).",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "airspeed",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "float",
                     units: :"m/s"
                   },
                   %{
                     constant_val: nil,
                     description: "Current ground speed.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "groundspeed",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "float",
                     units: :"m/s"
                   },
                   %{
                     constant_val: nil,
                     description: "Current heading in compass units (0-360, 0=north).",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "heading",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "int16_t",
                     units: :deg
                   },
                   %{
                     constant_val: nil,
                     description: "Current throttle setting (0 to 100).",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "throttle",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint16_t",
                     units: :%
                   },
                   %{
                     constant_val: nil,
                     description: "Current altitude (MSL).",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "alt",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "float",
                     units: :m
                   },
                   %{
                     constant_val: nil,
                     description: "Current climb rate.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "climb",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "float",
                     units: :"m/s"
                   }
                 ],
                 has_ext_fields: false,
                 id: 74,
                 name: "VFR_HUD"
               },
               %{
                 description: "Data packet, size 16.",
                 fields: [
                   %{
                     constant_val: nil,
                     description: "Data type.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "type",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint8_t",
                     units: nil
                   },
                   %{
                     constant_val: nil,
                     description: "Data length.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "len",
                     omit_arg: false,
                     ordinality: 1,
                     print_format: nil,
                     type: "uint8_t",
                     units: :bytes
                   },
                   %{
                     constant_val: nil,
                     description: "Raw data.",
                     display: nil,
                     enum: "",
                     is_extension: false,
                     name: "data",
                     omit_arg: false,
                     ordinality: 16,
                     print_format: nil,
                     type: "uint8_t",
                     units: nil
                   }
                 ],
                 has_ext_fields: false,
                 id: 169,
                 name: "DATA16"
               }
             ],
             version: "3"
           } = parse_mavlink_xml("#{@root_dir}/test/input/test_mavlink.xml")
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
            } = parse_mavlink_xml("#{@root_dir}/test/input/test_extensions.xml")
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
           } = parse_mavlink_xml(
             "#{@root_dir}/test/input/test_mavlink_include.xml"
           )
  end


end
