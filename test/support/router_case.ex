defmodule MAVLink.Test.RouterCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias MAVLink.Test.DialectFixture
  alias MAVLink.{Router, SerialConnection, TCPOutConnection, UDPInConnection, UDPOutConnection}

  using do
    quote do
      import MAVLink.Test.RouterCase
      import MAVLink.Test.FrameFixtures
      import MAVLink.Test.ConnectionStubs

      @moduletag :capture_log
    end
  end

  setup _tags do
    stop_children()
    clear_subscription_cache()
    dialect = DialectFixture.ensure_compiled!()
    Application.put_env(:mavlink, :dialect, dialect)

    {:ok, _} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)
    {:ok, _} =
      GenServer.start_link(
        MAVLink.LocalConnection,
        %{system: 245, component: 250, dialect: dialect},
        name: MAVLink.LocalConnection
      )

    {:ok, router} =
      GenServer.start_link(
        Router,
        %{
          dialect: dialect,
          system: 245,
          component: 250,
          connection_strings: []
        },
        [name: Router]
      )

    wait_for_local_connection()

    on_exit(fn -> stop_children() end)

    {:ok, router: router, dialect: dialect}
  end

  def clear_subscription_cache do
    case Process.whereis(MAVLink.SubscriptionCache) do
      nil -> :ok
      pid -> Agent.update(pid, fn _ -> [] end)
    end
  end

  def wait_for_local_connection do
    Enum.reduce_while(1..100, :error, fn _, _ ->
      if Process.whereis(MAVLink.LocalConnection) do
        {:halt, :ok}
      else
        Process.sleep(10)
        {:cont, :error}
      end
    end)
  end

  def stop_children do
    for name <- [Router, MAVLink.LocalConnection, MAVLink.RouteTable] do
      case Process.whereis(name) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5_000)
      end
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def router_state, do: :sys.get_state(Router)

  def connection_state(key), do: :sys.get_state(connection_pid!(key))

  def connection_pid!(key) do
    case Router.connection_pid(key) do
      pid when is_pid(pid) -> pid
      _ -> flunk("no connection registered for #{inspect(key)}")
    end
  end

  def route_for({sys, comp}) do
    case :ets.lookup(:mavlink_routes, {sys, comp}) do
      [{{^sys, ^comp}, {_pid, key}}] -> key
      [] -> nil
    end
  end

  def routes_map do
    :mavlink_routes
    |> :ets.tab2list()
    |> Enum.map(fn {{sys, comp}, {_pid, key}} -> {{sys, comp}, key} end)
    |> Map.new()
  end

  def add_connection(key, connection) do
    dialect = DialectFixture.ensure_compiled!()

    {:ok, pid} =
      case connection do
        nil ->
          {socket, ip, port} = key

          UDPInConnection.start_test(%{
            dialect: dialect,
            listen_address: ip,
            listen_port: port,
            socket: socket
          })

        %UDPInConnection{socket: socket, address: ip, port: port} ->
          UDPInConnection.start_test(%{
            dialect: dialect,
            listen_address: ip,
            listen_port: port,
            socket: socket,
            clients: %{{socket, ip, port} => connection}
          })

        %UDPOutConnection{socket: socket, address: ip, port: port} ->
          UDPOutConnection.start_test(%{
            dialect: dialect,
            socket: socket,
            address: ip,
            port: port,
            connection_key: key
          })

        %TCPOutConnection{socket: socket, address: ip, port: port, buffer: buffer} ->
          TCPOutConnection.start_test(%{
            dialect: dialect,
            socket: socket,
            address: ip,
            port: port,
            buffer: buffer,
            connection_key: key
          })

        %SerialConnection{port: port, baud: baud, uart: uart, buffer: buffer} ->
          SerialConnection.start_test(%{
            dialect: dialect,
            port: port,
            baud: baud,
            uart: uart,
            buffer: buffer,
            connection_key: key
          })
      end

    send(Router, {:register_connection, key, pid})
    Process.sleep(10)
    {:ok, pid}
  end
end
