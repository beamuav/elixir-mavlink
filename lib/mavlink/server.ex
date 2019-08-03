defmodule Mavlink.Server do
  @moduledoc false
  
  
  use GenServer
  
  import Mavlink.Utils, only: [parse_ip_address: 1]
  
  
  # Client API
  
  
  def start_link(state, opts \\ []) do
    GenServer.start_link(__MODULE__, state, [{:name, __MODULE__} | opts])
  end
  
  
  def connect(connection_string) do
    GenServer.call Mavlink.Server, {:connect, connection_string}
  end
  
  
  # Callbacks

  
  @impl true
  def init(state) do
    IO.inspect(state)
    {:ok, state}
  end

  
  @impl true
  def handle_call({:connect, connection_string}, from, state) do
    String.split(connection_string, ":") |> do_connect(state)
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end
  
  
  # Helpers
  
  
  defp do_connect([protocol, address, port], state) do
    case parse_ip_address(address) do
      {a, b, c, d} ->
        case Integer.parse(port) do
          :error ->
            {:reply, {:error, :invalid_port}, state}
          p when p > 0 ->
            do_connect(protocol, {a, b, c, d}, port, state)
          _ ->
            {:reply, {:error, :invalid_port}, state}
        end
      _ ->
        {:reply, {:error, :invalid_address}, state}
    end
  end
  
  defp do_connect("udpin", address, port, state) do
    {:reply, "udpin not implemented", state}
  end
  
  defp do_connect("udpout", address, port, state) do
    {:reply, "udpout not implemented", state}
  end
  
  defp do_connect("tcp", address, port, state) do
    {:reply, "tcp not implemented", state}
  end
  
  defp do_connect(_, _, _, state) do
    {:reply, {:error, :invalid_protocol}, state}
  end
  
  
  
  
  
  
  
end
