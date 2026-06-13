defmodule MAVLink.Connection do
  @moduledoc false

  @callback forward(struct(), MAVLink.Frame.t()) :: :ok
end
