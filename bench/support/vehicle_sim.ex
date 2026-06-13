defmodule MAVLink.Bench.VehicleSim do
  @moduledoc false

  def start_link(port) do
    Agent.start_link(fn -> %{port: port, socket: nil, client: nil} end)
  end

  def listen(agent) do
    Agent.update(agent, fn state ->
      {:ok, socket} = :gen_tcp.listen(state.port, [:binary, active: false, reuseaddr: true, backlog: 1])
      %{state | socket: socket}
    end)
  end

  def await_router_connect(agent, timeout_ms) do
    socket = Agent.get(agent, & &1.socket)

    case :gen_tcp.accept(socket, timeout_ms) do
      {:ok, client} ->
        Agent.update(agent, &Map.put(&1, :client, client))
        :ok

      {:error, _} = err ->
        err
    end
  end

  def flood(agent, raw_frame, count) do
    client = Agent.get(agent, & &1.client)
    data = :binary.copy(raw_frame, count)
    :gen_tcp.send(client, data)
  end

  def close(agent) do
    Agent.get(agent, fn %{socket: socket, client: client} ->
      if client, do: :gen_tcp.close(client)
      if socket, do: :gen_tcp.close(socket)
    end)
  end
end
