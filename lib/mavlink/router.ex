defmodule MAVLink.Router do
  @moduledoc false
  
  
  use GenServer
  
  alias Circuits.UART, as: UART
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1]
  
  
  # Client API
  
  
  def start_link(state, opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      state,
      [{:name, :"MAVLink.Router"} | opts])
  end
  
  
  def connect(connection_string) do
    GenServer.call __MODULE__, {:connect, connection_string}
  end
  
  
  # Callbacks

  
  @impl true
  def init(state) do
    {:ok, Map.merge(state, %{connections: %{}, targets: %{}})}
  end

  
  @impl true
  def handle_call({:connect, connection_string}, _from, state) do
    String.split(connection_string, ":,") |> do_connect(state)
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end
  
  
  # Helpers
  
  
  defp do_connect(["serial", port], state) do
    do_connect(["serial", port, "9600"], state)
  end
  
  defp do_connect(["serial", port, baud], state) do
    case {File.exists?(port), parse_positive_integer(baud)} do
      {false, _} ->
        {:reply, {:error, :port_doesnt_exist}, state}
      {_, :error} ->
        {:reply, {:error, :invalid_baud_rate}, state}
      {true, b} ->
        :ok = UART.open(UART, port, speed: b, active: true)
        {:reply,
          :ok,
          %{state | connections: %{
            state.connections | {:serial, port} => <<>>}
          }
        }
    end
  end
  
  defp do_connect([protocol, address, port], state) do
    case {parse_ip_address(address), parse_positive_integer(port)} do
      {{:error, :invalid_ip_address}, _}->
        {:reply, {:error, :invalid_ip_address}, state}
      {_, :error} ->
        {:reply, {:error, :invalid_port}, state}
      {ip, p} ->
        do_connect(protocol, ip, p, state)
    end
  end
  
  defp do_connect("udpin", address, port, state) do
    {:ok, socket} = :gen_udp.open(port, [:binary, ip: address, active: :true])
    {:reply,
      :ok,
      %{state | connections: %{
        state.connections | {:udpin, address, port} => {socket, <<>>}}
       }
    }
  end
  
  defp do_connect("udpout", address, port, state) do
    {:ok, socket} = :gen_udp.open(port, [:binary, ip: address, active: :true])
    {:reply,
      :ok,
      %{state | connections: %{
        state.connections | {:udpout, address, port} => {socket, <<>>}}
       }
    }
  end
  
  defp do_connect("tcp", _address, _port, state) do
    {:reply, "tcp not implemented", state}
  end
  
  defp do_connect(_, _, _, state) do
    {:reply, {:error, :invalid_protocol}, state}
  end
  
end
