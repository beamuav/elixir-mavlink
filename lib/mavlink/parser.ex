defmodule Mavlink.Parser do
  @moduledoc """
  Parse a mavlink xml file into an idiomatic Elixir representation:
  
  %{
      version: 0,
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
          name: :optical_flow,
          description: "Optical flow...",
          fields: [
            %{
                type: :uint16,
                ordinality: 0,
                name: :flow_x,
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
  
 
  import Enum, only: [empty?: 1]
  import List, only: [first: 1]
  import Record, only: [defrecord: 2, extract: 2]
  import Regex, only: [replace: 3]
  import String, only: [to_integer: 1, downcase: 1, to_atom: 1, split: 3, trim_trailing: 2]

  
  @xmerl_header "xmerl/include/xmerl.hrl"
  defrecord :xmlAttribute, extract(:xmlAttribute, from_lib: @xmerl_header)
  defrecord :xmlText, extract(:xmlText, from_lib: @xmerl_header)
  
  @spec parse_mavlink_xml(String.t) :: %{version: integer, dialect: integer, enums: [], messages: []} | {:error, :enoent}
  def parse_mavlink_xml(path) do
    case :xmerl_scan.file(path) do
      {defs, []} ->
        %{
          version:  :xmerl_xpath.string('/mavlink/version/text()', defs) |> extract_text |> to_integer,
          dialect:  :xmerl_xpath.string('/mavlink/dialect/text()', defs) |> extract_text |> to_integer,
          enums:    (for enum <- :xmerl_xpath.string('/mavlink/enums/enum', defs), do: parse_enum(enum)),
          messages: (for msg <- :xmerl_xpath.string('/mavlink/messages/message', defs), do: parse_message(msg))
        }
      {:error, :enoent} ->
        {:error, :enoent}
    end
  end
  
  
  defp parse_enum(element) do
    %{
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> downcase |> to_atom,
      description:  :xmerl_xpath.string('/enum/description/text()', element) |> extract_text |> nil_to_empty_string,
      entries:      (for entry <- :xmerl_xpath.string('/enum/entry', element), do: parse_entry(entry))
    }
  end
  
  
  defp parse_entry(element) do
    value_attr = :xmerl_xpath.string('@value', element) # Apparently optional in common.xml?
    %{
      value:        (if not empty?(value_attr), do: extract_text(value_attr) |> to_integer, else: nil),
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> downcase |> to_atom,
      description:  :xmerl_xpath.string('/entry/description/text()', element) |> extract_text |> nil_to_empty_string,
      params:       (for param <- :xmerl_xpath.string('/entry/param', element), do: parse_param(param))
    }
  end
  
  
  defp parse_param(element) do
    %{
      index:        :xmerl_xpath.string('@index', element) |> extract_text |> to_integer,
      description:  :xmerl_xpath.string('/param/text()', element) |> extract_text,
    }
  end
  
  
  defp parse_message(element) do
    %{
      id:           :xmerl_xpath.string('@id', element) |> extract_text |> to_integer,
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> downcase |> to_atom,
      description:  :xmerl_xpath.string('/message/description/text()', element) |> extract_text,
      fields:       (for field <- :xmerl_xpath.string('/message/field', element), do: parse_field(field))
    }
  end
  
  
  defp parse_field(element) do
    {type, ordinality} =
      :xmerl_xpath.string('@type', element)
      |> extract_text
      |> parse_type_ordinality

    %{
      type:         type,
      ordinality:   ordinality,
      name:         :xmerl_xpath.string('@name', element) |> extract_text |> to_atom,
      enum:         :xmerl_xpath.string('@enum', element) |> extract_text |> nil_to_empty_string |> downcase |> to_atom_or_nil,
      display:      :xmerl_xpath.string('@display', element) |> extract_text |> to_atom_or_nil,
      units:        :xmerl_xpath.string('@units', element) |> extract_text |> to_atom_or_nil,
      description:  :xmerl_xpath.string('/field/text()', element) |> extract_text
    }
  end
  
  
  defp parse_type_ordinality(type_string) do
    [type | ordinality] = type_string
      |> split(["[", "]"], trim: true)
      
    {
      type |> trim_trailing("_t") |> to_atom,
      cond do
        ordinality |> empty? ->
          0
        true ->
          ordinality |> first |> to_integer
      end
    }
  end
  
  
  defp extract_text([xmlText(value: value)]), do: clean_string(value)
  defp extract_text([xmlAttribute(value: value)]), do: clean_string(value)
  defp extract_text(_), do: nil
  
  defp clean_string(s) do
    trimmed = s |> List.to_string |> String.trim
    replace(~r/\s+/, trimmed, " ")
  end
  
  defp nil_to_empty_string(nil), do: ""
  defp nil_to_empty_string(value), do: value
  
  defp to_atom_or_nil(nil), do: nil
  defp to_atom_or_nil(""), do: nil
  defp to_atom_or_nil(value), do: to_atom(value)
  
end
