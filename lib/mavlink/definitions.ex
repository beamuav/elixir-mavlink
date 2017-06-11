defmodule Mavlink.Definitions do
  @moduledoc """
  Defines the mavlink macro which creates types
  and modules representing enums and messages in a
   mavlink xml file.
  """
  
   defmacro __using__(_options) do
    quote do
      import unquote(__MODULE__)
    end
  end
  
end