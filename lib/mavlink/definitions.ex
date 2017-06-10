defmodule Mavlink.Definitions do
  @moduledoc """
  Defines the load_definitions macro which creates types
  and modules representing enums and messages in a
   mavlink xml file.
  """
  
  require Record
  import Record, only: [defrecord: 2, extract: 2]
  import String, only: [to_integer: 1]
  
  
  defrecord :xmlAttribute, extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  defrecord :xmlText, extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  

  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
    end
  end
  

  def load_definitions(path) do
    {defs, _} = :xmerl_scan.file(path)
    %{
      version:  :xmerl_xpath.string('/mavlink/version/text()', defs) |> extract_text |> to_integer,
      dialect:  :xmerl_xpath.string('/mavlink/dialect/text()', defs) |> extract_text |> to_integer,
      enums:    (for enum <- :xmerl_xpath.string('/mavlink/enums/enum', defs), do: parse_enum(enum)),
      messages: (for msg <- :xmerl_xpath.string('/mavlink/messages/message', defs), do: parse_msg(msg))
    }
  end
  
  defp extract_text([xmlText(value: value)]), do: List.to_string(value)
  defp extract_text(_), do: nil
  
  defp parse_enum(element) do
    nil
  end
  
   defp parse_msg(element) do
    nil
  end
  
end