defmodule MAVLink.SerialConnection do
  @moduledoc """
  MAVLink.Router delegate for Serial connections
  """
  
  
  import MAVLink.Utils, only: [parse_positive_integer: 1]
  alias Circuits.UART, as: UART
  
  # TODO struct with a buffer
  
  
  def connect(state, ["serial", port]) do
    connect(state, ["serial", port, "9600"])
  end
  
  def connect(%MAVLink.Router{uarts: []}, ["serial", port, _]) do
    raise RuntimeError, message: "no available UARTS for serial connection #{port}, maximum is 4"
  end
  
  def connect(state = %MAVLink.Router{uarts: [next_free_uart | _free_uarts]}, ["serial", port, baud]) do
    attached_ports = UART.enumerate()
    case {Map.has_key?(attached_ports, port), parse_positive_integer(baud)} do
      {false, _} ->
        raise ArgumentError, message: "port #{port} not attached"
      {_, :error} ->
        raise ArgumentError, message: "invalid baud rate #{baud}"
      {true, parsed_baud} ->
        case UART.open(next_free_uart, port, speed: parsed_baud, active: true) do
          :ok ->
            put_in(state,
              [:connections, {:serial, port}],
              struct(MAVLink.SerialConnection, %{uart: next_free_uart}))
          {:error, _} ->
            raise RuntimeError, message: "could not open serial port #{port}"
        end
    end
  end
  
  
  def handle_info({:serial, _sock, _addr, _port, _}, state) do
    # TODO and that signature is wrong
    {:noreply, state}
  end
  

end
