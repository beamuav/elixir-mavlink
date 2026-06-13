defmodule MAVLink.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: :"MAVLink.Supervisor")
  end

  @impl true
  def init(_) do
    dialect = Application.get_env(:mavlink, :dialect)
    system = Application.get_env(:mavlink, :system_id)
    component = Application.get_env(:mavlink, :component_id)

    children = [
      :poolboy.child_spec(
        :worker,
        [
          name: {:local, MAVLink.UARTPool},
          worker_module: Circuits.UART,
          size: 0,
          max_overflow: 10
        ]
      ),
      MAVLink.RouteTable,
      {MAVLink.LocalConnection, %{system: system, component: component, dialect: dialect}},
      {
        MAVLink.Router,
        %{
          dialect: dialect,
          system: system,
          component: component,
          connection_strings: Application.get_env(:mavlink, :connections)
        }
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
