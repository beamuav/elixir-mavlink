defmodule MAVLink.Parser do
  @moduledoc """
  Parse a mavlink xml file into an idiomatic Elixir representation:
  
  %{
      version: 2,
      dialect: 0,
      enums: [
        %{
          name: :mav_autopilot,
          description: "Micro air vehicle...",
          entries: [
            %{
              value: 0,
              name: :mav_autopilot_generic,         (use atoms for identifiers)
              description: "Generic autopilot..."
              params: [                             (only used by commands)
                %{
                    index: 0,
                    description: ""
                 },
                 ... more entry params
              ]
             },
             ... more enum entries
          ]
         },
        ... more enums
      ],
      messages: [
        %{
          id: 0,
          name: "optical_flow",
          description: "Optical flow...",
          fields: [
            %{
                type: "uint16_t",
                ordinality: 1,
                name: "flow_x",
                units: "dpixels",                   (note: string not atom)
                description: "Flow in pixels..."
             },
             ... more message fields
          ]
         },
        ... more messages
      ]
   }
  """
  
 
  import Enum, only: [empty?: 1, reduce: 3, reverse: 1, map: 2, sort_by: 2, into: 3, filter: 2]
  import List, only: [first: 1]
  import Record, only: [defrecord: 2, extract: 2]
  import Regex, only: [replace: 3]
  import String, only: [to_integer: 1, downcase: 1, to_atom: 1, split: 3]

  
  @xmerl_header "xmerl/include/xmerl.hrl"
  defrecord :xmlElement, extract(:xmlElement, from_lib: @xmerl_header)
  defrecord :xmlAttribute, extract(:xmlAttribute, from_lib: @xmerl_header)
  defrecord :xmlText, extract(:xmlText, from_lib: @xmerl_header)
  
  @spec parse_mavlink_xml(String.t) :: %{version: integer, dialect: integer, enums: [ enum_description ], messages: [ message_description ]} | {:error, :enoent}
  def parse_mavlink_xml(path) do
    parse_mavlink_xml(path, %{}) |> Map.values |> combine_definitions
  end
  
  
  def parse_mavlink_xml(path, paths) do
    case Map.has_key?(paths, path) do
      true ->
        paths   # Don't include a file twice
    
      false ->
        case :xmerl_scan.file(path) do
          {defs, []} ->
            # Recursively add new includes to paths
            paths = reduce(
              :xmerl_xpath.string('/mavlink/include/text()', defs) |> map(&extract_text/1),
              paths,
              fn (next_include, acc) ->
                include_path = Path.dirname(path) <> "/" <> next_include
                parse_mavlink_xml(include_path, acc)
              end
            )
            
            # And add ourselves to paths if we're not already there through a circular dependency
            version = :xmerl_xpath.string('/mavlink/version/text()', defs) |> extract_text |> nil_to_zero_string
            Map.put_new(paths, path, %{
              version:  version,
              dialect:  :xmerl_xpath.string('/mavlink/dialect/text()', defs) |> extract_text |> nil_to_zero_string,
              enums:    (for enum <- :xmerl_xpath.string('/mavlink/enums/enum', defs), do: parse_enum(enum)),
              messages: (for msg <- :xmerl_xpath.string('/mavlink/messages/message', defs), do: parse_message(msg, version))
            })
            
          {:error, :enoent} ->
            Map.put(paths, path, {:error, "File '#{path}' does not exist"})
        end
    end
  end
  
  
  # See https://mavlink.io/en/guide/xml_schema.html, mavparse.py merge_enums() and
  # check_duplicates() for proper validation. If making changes to definitions test
  # first with mavgen for now.
  # TODO Handle missing includes without borking
  def combine_definitions([single_def]) do
    single_def
  end
  
  def combine_definitions([
    %{
      version:  v1,
      dialect:  d1,
      enums:    e1,
      messages: m1
     },
    %{
      version:  v2,
      dialect:  d2,
      enums:    e2,
      messages: m2
     } | more_definitions]) do
    combine_definitions([
      %{
        version:  max(v1, v2), # strings > nil
        dialect:  max(d1, d2),
        enums:    merge_enums(e1, e2),
        messages: sort_by(m1 ++ m2, & &1.id)
       } | more_definitions])
  end
  
  
  def merge_enums(as, bs) do
    a_index = into(as, %{}, fn (enum) -> {enum.name, enum} end)
    b_index = into(bs, %{}, fn (enum) -> {enum.name, enum} end)
    only_in_a = for name <- filter(Map.keys(a_index), & !Map.has_key?(b_index, &1)), do: a_index[name]
    only_in_b = for name <- filter(Map.keys(b_index), & !Map.has_key?(a_index, &1)), do: b_index[name]
    
    in_a_and_b = for name <- filter(Map.keys(a_index), & Map.has_key?(b_index, &1)) do
      %{a_index[name] | entries:  sort_by(a_index[name].entries ++ b_index[name].entries, & &1.value)}
    end
    
    sort_by(only_in_a ++ in_a_and_b ++ only_in_b, & &1.name)
  end
  
  
  @type enum_description :: %{
    name:         atom,
    description:  String.t,
    entries:      [ entry_description ]
  }
  
  @spec parse_enum(tuple) :: enum_description
  defp parse_enum(element) do
    %{
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> downcase |> to_atom,
      description:  :xmerl_xpath.string('/enum/description/text()', element) |> extract_text |> nil_to_empty_string,
      entries:      (for entry <- :xmerl_xpath.string('/enum/entry', element), do: parse_entry(entry))
    }
  end
  
  
  @type entry_description :: %{
    value:        integer | nil,
    name:         atom,
    description:  String.t,
    params:       [ param_description ]
  }
  
  @spec parse_entry(tuple) :: entry_description
  defp parse_entry(element) do
    value_attr = :xmerl_xpath.string('@value', element) # Apparently optional in common.xml?
    %{
      value:        (if not empty?(value_attr), do: extract_text(value_attr) |> to_integer, else: nil),
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> downcase |> to_atom,
      description:  :xmerl_xpath.string('/entry/description/text()', element) |> extract_text |> nil_to_empty_string,
      params:       (for param <- :xmerl_xpath.string('/entry/param', element), do: parse_param(param))
    }
  end
  
  
  @type param_description :: %{
    index:        integer,
    description:  String.t
  }
  
  @spec parse_param(tuple) :: param_description
  defp parse_param(element) do
    %{
      index:        :xmerl_xpath.string('@index', element) |> extract_text |> to_integer,
      description:  :xmerl_xpath.string('/param/text()', element) |> extract_text,
    }
  end
  
  
  @type message_description :: %{
    id:             integer,
    name:           String.t,
    description:    String.t,
    has_ext_fields: boolean,
    fields:         [ field_description ]
  }
  
  @spec parse_message(tuple, String.t) :: message_description
  defp parse_message(element, version) do
    message_description = reduce(
      xmlElement(element, :content),
      %{
        id:             :xmerl_xpath.string('@id', element) |> extract_text |> to_integer,
        name:           :xmerl_xpath.string('@name', element) |> extract_text,
        description:    :xmerl_xpath.string('/message/description/text()', element) |> extract_text,
        has_ext_fields: false,
        fields:         []
       },
      fn (next_child, acc) ->
        case xmlElement(next_child, :name) do
          :field ->
            %{acc | fields: [parse_field(next_child, version, acc.has_ext_fields) | acc.fields]}
          :extensions ->
            %{acc | has_ext_fields: true}
          _ ->
            acc
        end
      end)
    %{message_description | fields: reverse(message_description.fields)}
  end
  
  
  @type field_description :: %{
    type:         String.t,
    ordinality:   integer,
    omit_arg:     boolean,
    is_extension: boolean,
    constant_val: String.t | nil,
    name:         String.t,
    enum:         String.t,
    display:      :bitmask | nil,
    print_format: String.t | nil,
    units:        atom | nil,
    description:  String.t
  }
  
  @spec parse_field(tuple, binary(), boolean) :: field_description
  defp parse_field(element, version, is_extension_field) do
    {type, ordinality, omit_arg, constant_val} =
      :xmerl_xpath.string('@type', element)
      |> extract_text
      |> parse_type_ordinality_omit_arg_constant_val(version)

    %{
      type:         type,
      ordinality:   ordinality,
      omit_arg:     omit_arg,
      is_extension: is_extension_field,
      constant_val: constant_val,
      name:         :xmerl_xpath.string('@name', element) |> extract_text, # You can't downcase this, wrecks crc_extra calc for POWER_STATUS
      enum:         :xmerl_xpath.string('@enum', element) |> extract_text |> nil_to_empty_string |> downcase,
      display:      :xmerl_xpath.string('@display', element) |> extract_text |> to_atom_or_nil,
      print_format: :xmerl_xpath.string('@print_format', element) |> extract_text,
      units:        :xmerl_xpath.string('@units', element) |> extract_text |> to_atom_or_nil,
      description:  :xmerl_xpath.string('/field/text()', element) |> extract_text |> nil_to_empty_string
    }
  end
  
  
  @spec parse_type_ordinality_omit_arg_constant_val(String.t, String.t) :: {String.t, integer, boolean, String.t | nil}
  defp parse_type_ordinality_omit_arg_constant_val(type_string, version) do
    [type | ordinality] = type_string
      |> split(["[", "]"], trim: true)

    case type do
      "uint8_t_mavlink_version" ->
        {"uint8_t", 1, true, version}
      _ ->
        {
          type,
          cond do
            ordinality |> empty? ->
              1
            true ->
              ordinality |> first |> to_integer
          end,
          false,
          nil
        }
    end
  end
  
  
  # TODO Can't spec this without causing dialyzer "nil can't match binary" - Erlang types?
  defp extract_text([xml]), do: extract_text(xml)
  defp extract_text(xmlText(value: value)), do: clean_string(value)
  defp extract_text(xmlAttribute(value: value)), do: clean_string(value)
  defp extract_text(_), do: nil
  
  
  @spec clean_string([ char ] | binary) :: String.t
  defp clean_string(s) do
    trimmed = s |> List.to_string |> String.trim
    replace(~r/\s+/, trimmed, " ")
  end
  
  
  @spec nil_to_empty_string(String.t | nil) :: String.t
  defp nil_to_empty_string(nil), do: ""
  defp nil_to_empty_string(value) when is_binary(value), do: value
  
  @spec nil_to_zero_string(String.t | nil) :: String.t
  defp nil_to_zero_string(nil), do: "0"
  defp nil_to_zero_string(value) when is_binary(value), do: value
  
  
  @spec to_atom_or_nil(String.t | nil) :: atom | nil
  defp to_atom_or_nil(nil), do: nil
  defp to_atom_or_nil(""), do: nil
  defp to_atom_or_nil(value) when is_binary(value), do: to_atom(value)
  
end
