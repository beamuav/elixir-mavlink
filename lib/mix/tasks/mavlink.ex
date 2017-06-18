defmodule Mix.Tasks.Mavlink do
  use Mix.Task

  
  import Mavlink.Parser
  import Enum, only: [count: 1, join: 2, map: 2, filter: 2, filter_map: 3]
  import String, only: [trim: 1]


  @shortdoc "Generate Mavlink Module from XML"
  def run(["generate", path]) do
    %{
      version: version,
      dialect: dialect,
      enums: enums,
      messages: messages
     } = parse_mavlink_xml(path)
     
     enum_details = get_enum_details(enums)
     
     """
     defmodule Mavlink do
       
       @typedoc "An atom representing a Mavlink enumeration type"
       @type mav_enum_type :: #{map(enums, & ":#{&1[:name]}") |> join(" | ")}
       
       @typedoc "An atom representing a Mavlink enumeration type value"
       @type mav_enum_value :: #{map(enums, & "#{&1[:name]}") |> join(" | ")}
       
       #{enum_details |> map(& &1[:type]) |> join("\n  ")}
       
       @typedoc "A parameter description"
       @type param_description :: {integer, String.t}
       @typedoc "A list of parameter descriptions"
       @type param_description_list :: [param_description]
       
       @doc "Mavlink version"
       @spec mavlink_version() :: integer
       def mavlink_version(), do: #{version}
       
       @doc "Mavlink dialect"
       @spec mavlink_dialect() :: integer
       def mavlink_dialect(), do: #{dialect}
       
       @doc "Return a String description of a Mavlink enumeration"
       @spec describe(mav_enum_type | mav_enum_value) :: String.t
       #{enum_details |> map(& &1[:describe]) |> join("\n  ") |> trim}
       
       @doc "Return keyword list of mav_cmd parameters"
       @spec describe_params(mav_cmd) :: param_description_list
       #{enum_details |> map(& &1[:describe_params]) |> join("\n  ") |> trim}
       
       @doc "Return encoded integer value used in a Mavlink message for an enumeration value"
       @spec encode(mav_enum_value) :: integer
       #{enum_details |> map(& &1[:encode]) |> join("\n  ") |> trim}
       
       @doc "Return the atom representation of a Mavlink enumeration value from the enumeration type and encoded integer"
       @spec decode(mav_enum_type, integer) :: mav_enum_value
       #{enum_details |> map(& &1[:decode]) |> join("\n  ") |> trim}
       
     end
     """
     
  end
  
  
  defp get_enum_details(enums) do
    for enum <- enums do
      %{
        name: name,
        description: description,
        entries: entries
      } = enum
      
      entry_details = get_entry_details(name, entries)
      
      %{
        type: ~s/@typedoc "#{description}"\n  / <>
          ~s/@type #{name} :: / <>
          (map(entry_details, & ":#{&1[:name]}") |> join(" | ")),
          
        describe: ~s/def describe(:#{name}), do: "#{description}"\n  / <>
          (map(entry_details, & &1[:describe])
          |> join("\n  ")),
          
        describe_params: filter_map(entry_details, & &1 != nil,& &1[:describe_params])
          |> join("\n  "),
          
        encode: map(entry_details, & &1[:encode])
          |> join("\n  "),
        
        decode: map(entry_details, & &1[:decode])
          |> join("\n  ")
      }
    end
  end
  
  
  defp get_entry_details(enum_name, entries) do
    for entry <- entries do
      %{
        name: entry_name,
        description: entry_description,
        value: entry_value,
        params: entry_params
      } = entry
      
      %{
        name: entry_name,
        describe: ~s/def describe(:#{entry_name}), do: "#{entry_description}"/,
        describe_params: get_param_details(entry_name, entry_params),
        encode: ~s/def encode(:#{entry_name}), do: #{entry_value}/,
        decode: ~s/def decode(:#{enum_name}, #{entry_value}), do: :#{entry_name}/
      }
    end
  end
  
  
  defp get_param_details(entry_name, entry_params) do
    cond do
      count(entry_params) == 0 ->
        nil
      true ->
        ~s/def describe_params(:#{entry_name}), do: [/ <>
        (map(entry_params, & ~s/#{&1[:index]}: "#{&1[:description]}"/) |> join(", ")) <>
        ~s/]/
    end
  end
  
end
