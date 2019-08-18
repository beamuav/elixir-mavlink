defmodule Mix.Tasks.Build do
  use Mix.Task

  @doc """
  
  """
  @shortdoc "Generate Elixir Module from MAVLink dialect XML"
  @spec run([String.t]) :: :ok
  @impl Mix.Task
  
  def run(_) do
    MAVLink.Writer.create("test/input/ardupilotmega.xml", "lib/mavlink/dialect/apm.ex", "MAVLink.Dialect.APM")
  end
end
