defmodule MAVLink.Supervisor do
  @moduledoc false
  
  use Supervisor


  
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: :"MAVLink.Supervisor")
  end

  @impl true
  def init(_) do
    children = [
      %{
        id: MAVLink_UART_1,
        start: {Circuits.UART, :start_link, [[name: :"MAVLink.UART.1"]]}
      },
      %{
        id: MAVLink_UART_2,
        start: {Circuits.UART, :start_link, [[name: :"MAVLink.UART.2"]]}
      },
      %{
        id: MAVLink_UART_3,
        start: {Circuits.UART, :start_link, [[name: :"MAVLink.UART.3"]]}
      },
      %{
        id: MAVLink_UART_4,
        start: {Circuits.UART, :start_link, [[name: :"MAVLink.UART.4"]]}
      },
      {
        MAVLink.Router,
        %{
          dialect: Application.get_env(:mavlink, :dialect),
          system: Application.get_env(:mavlink, :system),
          component: Application.get_env(:mavlink, :component),
          connections: Application.get_env(:mavlink, :connections),
          uarts: [
            :"MAVLink.UART.1",
            :"MAVLink.UART.2",
            :"MAVLink.UART.3",
            :"MAVLink.UART.4"
          ]
        }
      }
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
