defmodule Mavlink.Definitions do
  @moduledoc """
  Defines the load_definitions macro which creates types
  and modules representing enums and messages in a
   mavlink xml file.
  """
  
  require Record
  import Record, only: [defrecord: 2, extract_all: 1]
  
  for {rec_name, fields} <- extract_all( from_lib: "xmerl/include/xmerl.hrl") do
    defrecord rec_name, fields
  end


  defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
    end
  end
  

  def load_definitions(path) do
    {
      xmlElement(
        name: :mavlink,
        content: [
          _,  # whitespace
          xmlElement(
            name: :version,
            content: [
              xmlText(
                value: version
              )
            ]
          ),
          _,  # whitespace
          xmlElement(
            name: :dialect,
            content: [
              xmlText(
                value: dialect
              )
            ]
          ),
          _,  # whitespace
          xmlElement(
            name: :enums,
            content: enums
          ),
          _,  # whitespace
          xmlElement(
            name: :messages,
            content: messages
          )| _
        ]
      ),
      _
    } = :xmerl_scan.file(path)
    %{
      version: List.to_integer(version),
      dialect: List.to_integer(dialect),
      enums: enums,
      messages: messages
    }
  end
  
end