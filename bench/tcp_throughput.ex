defmodule MAVLink.Bench.TCPThroughput do
  @moduledoc false

  def run do
    Code.require_file("test/support/dialect_fixture.ex", File.cwd!())
    Code.require_file("test/support/frame_fixtures.ex", File.cwd!())

    alias MAVLink.Test.{DialectFixture, FrameFixtures}

    port = 15_760
    warmup_s = 2
    measure_s = 5
    dialect = DialectFixture.ensure_compiled!()
    raw = FrameFixtures.heartbeat_v2_raw(source_system: 1, source_component: 1)

    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, backlog: 1])

    {:ok, router} =
      GenServer.start_link(
        MAVLink.Router,
        %{
          dialect: dialect,
          system: 245,
          component: 250,
          connection_strings: ["tcpout:127.0.0.1:#{port}"]
        },
        [name: MAVLink.Router]
      )

    {:ok, client} = :gen_tcp.accept(listen_socket, 5_000)
    :ok = :inet.setopts(client, active: false)
    Process.sleep(300)

    {:ok, counter} = Agent.start_link(fn -> 0 end)

    counter_pid =
      spawn(fn ->
        :ok = MAVLink.Router.subscribe(message: TestMavlink.Message.Heartbeat, source_system: 1)
        count_loop(counter)
      end)

    Process.sleep(100)
    for _ <- 1..10, do: :gen_tcp.send(client, raw)
    Process.sleep(200)

    flooder =
      spawn(fn ->
        flood_loop(client, raw)
      end)

    Process.sleep(warmup_s * 1000)
    Agent.update(counter, fn _ -> 0 end)

    start_ms = System.monotonic_time(:millisecond)
    Process.sleep(measure_s * 1000)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms
    count = Agent.get(counter, & &1)
    send(flooder, :stop)

    rate = if elapsed_ms > 0, do: count / (elapsed_ms / 1000), else: 0.0

    IO.puts("TCP throughput benchmark")
    IO.puts("  Elixir #{System.version()} OTP #{System.otp_release()}")
    IO.puts("  Measurement window: #{elapsed_ms} ms")
    IO.puts("  Messages received: #{count}")
    IO.puts("  Rate: #{Float.round(rate, 1)} msg/s")

    File.mkdir_p!("bench/results")

    File.write!(
      "bench/results/baseline.txt",
      """
      TCP throughput benchmark (baseline)
      Elixir #{System.version()} OTP #{System.otp_release()}
      Measurement window: #{elapsed_ms} ms
      Messages received: #{count}
      Rate: #{Float.round(rate, 1)} msg/s
      """
    )

    IO.puts("\nWrote bench/results/baseline.txt")

    Process.exit(counter_pid, :kill)
    Process.exit(flooder, :kill)
    :gen_tcp.close(client)
    :gen_tcp.close(listen_socket)
    GenServer.stop(router, :brutal_kill)
  end

  defp count_loop(counter) do
    receive do
      _ ->
        Agent.update(counter, &(&1 + 1))
        count_loop(counter)
    end
  end

  defp flood_loop(client, raw) do
    :gen_tcp.send(client, raw)

    receive do
      :stop -> :ok
    after
      0 -> flood_loop(client, raw)
    end
  rescue
    _ -> :ok
  end
end
