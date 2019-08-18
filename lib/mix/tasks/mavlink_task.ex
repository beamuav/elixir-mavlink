defmodule Mix.Tasks.Mavlink do
  use Mix.Task

  @doc """
  mix mavlink test/input/ardupilotmega.xml lib/mavlink/dialect/apm.ex MAVLink.Dialect.APM 
  """
  @shortdoc "Generate Elixir Module from MAVLink dialect XML"
  @spec run([String.t]) :: :ok
  @impl Mix.Task
  
  def run([dialect_xml_path, output_ex_source_path, module_name]) do
    MAVLink.Writer.create(dialect_xml_path, output_ex_source_path, module_name)
  end
end
