defmodule MAVLink.Bench.RoutingMicrobench do
  @moduledoc false

  alias MAVLink.RouteTable
  alias MAVLink.Test.DialectFixture

  def run(opts \\ []) do
    Code.require_file("test/support/dialect_fixture.ex", File.cwd!())
    Code.require_file("test/support/frame_fixtures.ex", File.cwd!())

    import MAVLink.Test.FrameFixtures

    subscribers = Keyword.get(opts, :subscribers, 50)
    frames = Keyword.get(opts, :frames, 100_000)
    label = Keyword.get(opts, :label, "routing")
    output = Keyword.get(opts, :output_file, "bench/results/routing-#{label}.txt")

    DialectFixture.ensure_compiled!()
    {:ok, _} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)

    pids =
      for i <- 1..subscribers do
        pid =
          spawn(fn ->
            receive do
              :stop -> :ok
            end
          end)

        vehicle = rem(i - 1, 8) + 1

        :ok =
          MAVLink.RouteTable.subscribe(
            %{
              message: TestMavlink.Message.VfrHud,
              source_system: vehicle,
              source_component: 0,
              target_system: 0,
              target_component: 0,
              as_frame: false
            },
            pid
          )

        pid
      end

    frame =
      vfr_hud_frame(source_system: 3)
      |> Map.put(:message, struct(TestMavlink.Message.VfrHud, [
        airspeed: 10.0,
        groundspeed: 9.0,
        heading: 90,
        throttle: 50,
        alt: 100.0,
        climb: 0.2
      ]))

    {micros, results} = :timer.tc(fn -> Enum.map(1..frames, fn _ -> RouteTable.matching_subscribers(frame) end) end)

    matches = Enum.count(results, fn list -> length(list) > 0 end)
    rate = frames / (micros / 1_000_000)

    report = """
    Routing microbench (#{label})
    Elixir #{System.version()} OTP #{System.otp_release()}
    Subscribers: #{subscribers}
    Frames matched: #{frames}
    Non-empty matches: #{matches}
    matching_subscribers calls: #{frames}
    Elapsed: #{Float.round(micros / 1000, 1)} ms
    Rate: #{Float.round(rate, 1)} lookups/s
    ETS subscribers: #{ets_size(:mavlink_subscribers)}
    ETS subscriber_index: #{ets_size(:mavlink_subscriber_index)}
    """

    IO.puts(report)
    File.mkdir_p!("bench/results")
    File.write!(output, report)
    IO.puts("Wrote #{output}")

    for pid <- pids, do: send(pid, :stop)
    GenServer.stop(MAVLink.RouteTable, :normal, 1_000)
    :ok
  end

  defp ets_size(table) do
    case :ets.info(table, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
