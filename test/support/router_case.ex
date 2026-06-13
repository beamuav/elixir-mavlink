defmodule MAVLink.Test.RouterCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias MAVLink.Test.DialectFixture

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

    {:ok, _} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)
    {:ok, _} =
      GenServer.start_link(
        MAVLink.LocalConnection,
        %{system: 245, component: 250, dialect: dialect},
        name: MAVLink.LocalConnection
      )

    {:ok, router} =
      GenServer.start_link(
        MAVLink.Router,
        %{
          dialect: dialect,
          system: 245,
          component: 250,
          connection_strings: []
        },
        [name: MAVLink.Router]
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
    for name <- [MAVLink.Router, MAVLink.LocalConnection, MAVLink.RouteTable] do
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

  def router_state, do: :sys.get_state(MAVLink.Router)

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
    send(MAVLink.Router, {:add_connection, key, connection})
    Process.sleep(10)
  end
end
