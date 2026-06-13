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
    stop_router()
    clear_subscription_cache()
    dialect = DialectFixture.ensure_compiled!()

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

    on_exit(fn -> stop_router() end)

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
      if Map.has_key?(router_state().connections, :local) do
        {:halt, :ok}
      else
        Process.sleep(10)
        {:cont, :error}
      end
    end)
  end

  def stop_router do
    case Process.whereis(MAVLink.Router) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def router_state, do: :sys.get_state(MAVLink.Router)

  def add_connection(key, connection) do
    send(MAVLink.Router, {:add_connection, key, connection})
    Process.sleep(10)
  end
end
