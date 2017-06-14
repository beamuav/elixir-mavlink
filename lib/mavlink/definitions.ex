defmodule Mavlink.Definitions do
  @moduledoc """
  Defines the mavlink macro which creates types
  and modules representing enums and messages in a
   mavlink xml file.
  """
  
  
  import Mavlink.Parser
  
  
  @external_resource mavlink_path = Path.join([__DIR__, "../../config/mavlink.xml"])
  @mavlink_definitions parse_mavlink_xml(mavlink_path)
  
  
   defmacro __using__(_options) do
    # Global details
    %{
      version: version,
      dialect: dialect,
      enums: enums,
      messages: messages
     } = @mavlink_definitions
     
    # Enumeration Details
    enum_details = get_enum_details(enums)
    for enum_detail <- enum_details do
      Map.get(enum_detail, :describe_kw)
    end
    # Output definitions, grouping similar functions etc
    quote do
      @mavlink_version  unquote(version)
      @mavlink_dialect  unquote(dialect)
      unquote_splicing(for enum_detail <- enum_details, do: Map.get(enum_detail, :type_ast))
      unquote_splicing(for enum_detail <- enum_details, do: Map.get(enum_detail, :value_ast))
      def describe(key) do
        unquote({
          :%{}, [],
          for enum_detail <- enum_details do
            Map.get(enum_detail, :describe_kw)
          end |> List.flatten})
        |> Map.get(key)
      end

    end #|> Macro.to_string |> IO.puts
    
  end
  
  
  defp get_enum_details(enums) do
    for enum <- enums do
      %{
        name: name,
        description: description,
        entries: entries
      } = enum
      
      # Entry Details
      entry_details = get_entry_details(entries)
      
      # Add Entry Details into Enum Details
      %{
        type_ast: quote do
          @typedoc unquote(description)
          @type unquote({name, [], nil}) :: unquote(
            type_atom_list(Enum.map(entry_details, & &1[:name])))
        end,
        describe_kw: [{name, description}] ++
           Enum.map(entry_details, & &1[:describe_kw]),
        value_ast: quote do
          unquote(Enum.map(entry_details, & &1[:value_ast]))
        end
      }
    end
  end
  
  
  defp get_entry_details(entries) do
    for entry <- entries do
      %{
        name: entry_name,
        description: entry_description,
        value: entry_value,
        params: entry_params
      } = entry
      
      # Param Details
      param_details = get_param_details(entry_name, entry_params)
      
      %{
        name: entry_name,
        describe_kw: {entry_name, entry_description},
        value_ast: quote do
          def value(unquote(entry_name)), do: unquote(entry_value)
        end
      }
      #def describe(unquote(entry_name), _), do: ""
    end
  end
  
  
  defp get_param_details(entry_name, entry_params) do
    for param <- entry_params do
      %{
        index: param_index,
        description: param_description
       } = param
       
      %{
        #describe_param_dict: Keyword.put(Keyword.new, {entry_name, param_index}, param_description)
       }
    end
  end
  
  
  # Helper function to build recursive AST for :a | :b | :c expression
  defp type_atom_list([a]) do
    a
  end
  
  defp type_atom_list([a, b]) do
    {:|, [], [a, b]}
  end
  
  defp type_atom_list([a | tail]) do
    {:|, [], [a, type_atom_list(tail)]}
  end
  
  
  # Helper function to concatenate list of keywords
  defp concat_kw_list([]) do
    Keyword.new
  end
  
  defp concat_kw_list([a]) do
    a
  end
  
  defp concat_kw_list([a, [b] | tail]) do
    concat_kw_list([Keyword.merge(a, b), tail])
  end
  
end