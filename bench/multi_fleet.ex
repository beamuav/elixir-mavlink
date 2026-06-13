defmodule MAVLink.Bench.MultiFleet do
  @moduledoc false

  alias MAVLink.Bench.GCSCounter

  @default_vehicles 4
  @default_gcs 5
  @default_base_port 15_800
  @default_warmup_s 2
  @default_measure_s 5

  def run_throughput(opts \\ []) do
    Code.require_file("test/support/dialect_fixture.ex", File.cwd!())
    Code.require_file("test/support/frame_fixtures.ex", File.cwd!())
    Code.require_file("bench/support/gcs_counter.ex", File.cwd!())

    config = config(opts)
    setup = start_scenario(config)

    Process.sleep(config.warmup_s * 1000)
    :ok = GCSCounter.reset_all(setup.counter, setup.gcs_count)

    start_ms = System.monotonic_time(:millisecond)
    Process.sleep(config.measure_s * 1000)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms

    per_gcs = GCSCounter.get_all(setup.counter, setup.gcs_count)
    total = Enum.reduce(per_gcs, 0, fn {_slot, count}, acc -> acc + count end)
    rate = if elapsed_ms > 0, do: total / (elapsed_ms / 1000), else: 0.0

    report = format_throughput_report(config, elapsed_ms, per_gcs, total, rate, setup)
    IO.puts(report)
    File.mkdir_p!("bench/results")
    File.write!(config.output_file, report)
    IO.puts("\nWrote #{config.output_file}")

    cleanup(setup)
    :ok
  end

  def run_profile(opts \\ []) do
    Code.require_file("test/support/dialect_fixture.ex", File.cwd!())
    Code.require_file("test/support/frame_fixtures.ex", File.cwd!())
    Code.require_file("bench/support/gcs_counter.ex", File.cwd!())

    config = config(opts)
    setup = start_scenario(config)
    Process.sleep(config.warmup_s * 1000)

    profile_pids = profile_targets(setup)
    sampler = start_sampler(profile_pids)

    :eprof.start()
    :profiling = :eprof.start_profiling(profile_pids)
    :cprof.start()

    :ok = GCSCounter.reset_all(setup.counter, setup.gcs_count)
    start_ms = System.monotonic_time(:millisecond)
    Process.sleep(config.measure_s * 1000)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms

    per_gcs = GCSCounter.get_all(setup.counter, setup.gcs_count)
    total = Enum.reduce(per_gcs, 0, fn {_slot, count}, acc -> acc + count end)
    rate = if elapsed_ms > 0, do: total / (elapsed_ms / 1000), else: 0.0

    :cprof.stop()
    :eprof.stop_profiling()
    eprof_report = capture_eprof()
    cprof_report = capture_cprof()
    queue_samples = stop_sampler(sampler)

    report =
      format_profile_report(config, elapsed_ms, per_gcs, total, rate, setup, %{
        profile_pids: profile_pids,
        eprof_report: eprof_report,
        cprof_report: cprof_report,
        queue_samples: queue_samples
      })

    IO.puts(report)
    File.mkdir_p!("bench/results")
    File.write!(config.output_file, report)
    IO.puts("\nWrote #{config.output_file}")

    cleanup(setup)
    :ok
  end

  def config(opts) do
    vehicles = Keyword.get(opts, :vehicles, @default_vehicles)
    gcs_count = Keyword.get(opts, :gcs_count, @default_gcs)
    base_port = Keyword.get(opts, :base_port, @default_base_port)

    %{
      label: Keyword.get(opts, :label, "fleet"),
      output_file: Keyword.get(opts, :output_file, "bench/results/fleet-#{Keyword.get(opts, :label, "fleet")}.txt"),
      vehicles: vehicles,
      gcs_count: gcs_count,
      base_port: base_port,
      warmup_s: Keyword.get(opts, :warmup_s, @default_warmup_s),
      measure_s: Keyword.get(opts, :measure_s, @default_measure_s),
      dialect: MAVLink.Test.DialectFixture.ensure_compiled!()
    }
  end

  def start_scenario(config) do
    listen_sockets =
      for v <- 1..config.vehicles do
        port = config.base_port + v - 1
        {:ok, socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, backlog: 1])
        {v, port, socket}
      end

    {:ok, _} = DynamicSupervisor.start_link(MAVLink.ConnectionSupervisor, [], name: MAVLink.ConnectionSupervisor)
    {:ok, _} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)

    {:ok, _} =
      GenServer.start_link(
        MAVLink.LocalConnection,
        %{system: 245, component: 250, dialect: config.dialect},
        name: MAVLink.LocalConnection
      )

    connection_strings =
      Enum.map(listen_sockets, fn {_v, port, _socket} ->
        "tcpout:127.0.0.1:#{port}"
      end)

    {:ok, router} =
      GenServer.start_link(
        MAVLink.Router,
        %{
          dialect: config.dialect,
          system: 245,
          component: 250,
          connection_strings: connection_strings
        },
        name: MAVLink.Router
      )

    Process.sleep(500)

    clients = await_clients(listen_sockets, 15_000)

    {:ok, counter} = GCSCounter.start_link(config.gcs_count)

    gcs_pids = start_gcs_subscribers(counter, config)
    Process.sleep(300)

    streams =
      Map.new(clients, fn {vehicle_id, _client} ->
        {vehicle_id, MAVLink.Test.FrameFixtures.vehicle_telemetry_burst(vehicle_id)}
      end)

    for {vehicle_id, client} <- clients, raw <- Map.fetch!(streams, vehicle_id) do
      :gen_tcp.send(client, raw)
    end

    Process.sleep(200)

    flooder_pids =
      Enum.map(clients, fn {vehicle_id, client} ->
        stream = Map.fetch!(streams, vehicle_id)

        spawn(fn ->
          flood_vehicle(client, stream)
        end)
      end)

    %{
      config: config,
      router: router,
      listen_sockets: listen_sockets,
      clients: clients,
      counter: counter,
      gcs_pids: gcs_pids,
      flooder_pids: flooder_pids,
      gcs_count: config.gcs_count
    }
  end

  defp await_clients(listen_sockets, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Enum.map(listen_sockets, fn {vehicle_id, _port, listen_socket} ->
      await_client(listen_socket, vehicle_id, deadline)
    end)
  end

  defp await_client(listen_socket, vehicle_id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    case :gen_tcp.accept(listen_socket, max(remaining, 1)) do
      {:ok, client} ->
        :ok = :inet.setopts(client, active: false)
        {vehicle_id, client}

      {:error, :timeout} when remaining > 0 ->
        Process.sleep(50)
        await_client(listen_socket, vehicle_id, deadline)

      other ->
        raise "vehicle #{vehicle_id} TCP accept failed: #{inspect(other)}"
    end
  end

  defp start_gcs_subscribers(counter, %{vehicles: vehicles, gcs_count: gcs_count}) do
    wildcard_slots = max(gcs_count - vehicles, 0)

    per_vehicle =
      for slot <- 1..min(vehicles, gcs_count) do
        GCSCounter.start_subscriber(counter, slot, fn ->
          MAVLink.Router.subscribe(
            message: TestMavlink.Message.VfrHud,
            source_system: slot
          )
        end)
      end

    wildcard =
      if wildcard_slots > 0 do
        [
          GCSCounter.start_subscriber(counter, vehicles + 1, fn ->
            MAVLink.Router.subscribe(message: nil, source_system: 0)
          end)
        ]
      else
        []
      end

    per_vehicle ++ wildcard
  end

  defp flood_vehicle(client, stream) do
    count = length(stream)
    flood_vehicle(client, stream, 0, count)
  end

  defp flood_vehicle(client, stream, index, count) do
    raw = Enum.at(stream, rem(index, count))
    :gen_tcp.send(client, raw)

    receive do
      :stop -> :ok
    after
      0 -> flood_vehicle(client, stream, index + 1, count)
    end
  rescue
    _ -> :ok
  end

  defp profile_targets(setup) do
    wire_pids =
      MAVLink.RouteTable.all_wire_peers()
      |> Enum.map(fn {pid, _} -> pid end)
      |> Enum.uniq()

    route_table_pid = Process.whereis(MAVLink.RouteTable)

    ([setup.router, route_table_pid] ++ setup.gcs_pids ++ wire_pids)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&Process.alive?/1)
  end

  defp start_sampler(pids) do
    parent = self()

    spawn(fn ->
      sample_loop(parent, pids, [])
    end)
  end

  defp sample_loop(parent, pids, acc) do
    sample =
      Enum.map(pids, fn pid ->
        info = Process.info(pid, [:message_queue_len, :reductions, :current_function])
        {pid, info}
      end)

    receive do
      :stop ->
        send(parent, {:samples, Enum.reverse([{System.monotonic_time(:millisecond), sample} | acc])})
    after
      100 ->
        sample_loop(parent, pids, [{System.monotonic_time(:millisecond), sample} | acc])
    end
  end

  defp stop_sampler(sampler) do
    send(sampler, :stop)

    receive do
      {:samples, samples} -> samples
    after
      1000 -> []
    end
  end

  defp capture_eprof do
    try do
      ExUnit.CaptureIO.capture_io(fn -> :eprof.analyze([{:sort, :time}]) end)
    rescue
      _ -> "(eprof output not captured)"
    end
  end

  defp capture_cprof do
    case :cprof.analyse() do
      {total, counts} ->
        lines =
          counts
          |> Enum.flat_map(fn {mod, funs} ->
            Enum.map(funs, fn {fun, arity, count} ->
              {count, mod, fun, arity}
            end)
          end)
          |> Enum.sort_by(fn {count, _, _, _} -> -count end)
          |> Enum.take(50)
          |> Enum.map(fn {count, mod, fun, arity} ->
            "#{count} #{inspect(mod)}:#{fun}/#{arity}"
          end)

        "total_calls=#{total}\n" <> Enum.join(lines, "\n")

      other ->
        inspect(other)
    end
  end

  defp format_throughput_report(config, elapsed_ms, per_gcs, total, rate, setup) do
    """
    Multi-vehicle / multi-GCS throughput (#{config.label})
    Elixir #{System.version()} OTP #{System.otp_release()}
    Vehicles: #{config.vehicles}  GCS subscribers: #{config.gcs_count}
    Message mix per vehicle: 3x VFR_HUD, 1x HEARTBEAT, 1x DATA16 (rotated)
    Measurement window: #{elapsed_ms} ms
    Total messages delivered: #{total}
    Aggregate rate: #{Float.round(rate, 1)} msg/s
    Per-GCS deliveries:
    #{format_per_gcs(per_gcs, config)}
    ETS sizes: routes=#{ets_size(:mavlink_routes)} subscribers=#{ets_size(:mavlink_subscribers)} peers=#{ets_size(:mavlink_peers)}
    Wire connections: #{length(setup.clients)}
    """
  end

  defp format_profile_report(config, elapsed_ms, per_gcs, total, rate, _setup, profile) do
    pid_lines =
      Enum.map(profile.profile_pids, fn pid ->
        info = Process.info(pid, [:registered_name, :current_function, :message_queue_len, :reductions])
        "  #{inspect(pid)} #{inspect(info)}"
      end)

    """
    Multi-vehicle / multi-GCS profile (#{config.label})
    Elixir #{System.version()} OTP #{System.otp_release()}
    Vehicles: #{config.vehicles}  GCS subscribers: #{config.gcs_count}
    Message mix per vehicle: 3x VFR_HUD, 1x HEARTBEAT, 1x DATA16 (rotated)
    Measurement window: #{elapsed_ms} ms
    Total messages delivered: #{total}
    Aggregate rate: #{Float.round(rate, 1)} msg/s
    Per-GCS deliveries:
    #{format_per_gcs(per_gcs, config)}
    ETS sizes: routes=#{ets_size(:mavlink_routes)} subscribers=#{ets_size(:mavlink_subscribers)} subscriber_index=#{ets_size(:mavlink_subscriber_index)} peers=#{ets_size(:mavlink_peers)}

    Profiled processes:
    #{Enum.join(pid_lines, "\n")}

    Message queue samples (max len per process):
    #{summarize_queues(profile.queue_samples, profile.profile_pids)}

    Reductions delta over window:
    #{summarize_reductions(profile.queue_samples, profile.profile_pids)}

    == eprof (profiled processes) ==
    #{profile.eprof_report}

    == cprof (top calls, whole VM) ==
    #{profile.cprof_report}
    """
  end

  defp format_per_gcs(per_gcs, %{vehicles: vehicles, gcs_count: gcs_count}) do
    per_gcs
    |> Enum.map(fn {slot, count} ->
      label =
        cond do
          slot <= vehicles -> "  GCS #{slot} (VFR_HUD vehicle #{slot}): #{count}"
          slot == vehicles + 1 and gcs_count > vehicles -> "  GCS #{slot} (wildcard logger): #{count}"
          true -> "  GCS #{slot}: #{count}"
        end

      label
    end)
    |> Enum.join("\n")
  end

  defp ets_size(table) do
    case :ets.info(table, :size) do
      :undefined -> 0
      size -> size
    end
  end

  defp summarize_queues(samples, pids) do
    max_by_pid =
      Enum.reduce(samples, %{}, fn
        {_ts, entries}, acc when is_list(entries) ->
          Enum.reduce(entries, acc, fn {pid, info}, inner ->
            len = Keyword.get(info, :message_queue_len, 0)
            Map.update(inner, pid, len, &max(&1, len))
          end)

        _, acc ->
          acc
      end)

    pids
    |> Enum.map(fn pid ->
      max_len = Map.get(max_by_pid, pid, 0)
      name = pid |> Process.info(:registered_name) |> label_pid()
      "  #{name}: max_queue=#{max_len}"
    end)
    |> Enum.join("\n")
  end

  defp summarize_reductions(samples, pids) do
    {first, last} =
      case {List.first(samples), List.last(samples)} do
        {{_, first_entries}, {_, last_entries}} when is_list(first_entries) and is_list(last_entries) ->
          {Map.new(first_entries), Map.new(last_entries)}

        _ ->
          {%{}, %{}}
      end

    pids
    |> Enum.map(fn pid ->
      r0 = first |> Map.get(pid, []) |> Keyword.get(:reductions, 0)
      r1 = last |> Map.get(pid, []) |> Keyword.get(:reductions, 0)
      name = pid |> Process.info(:registered_name) |> label_pid()
      "  #{name}: reductions_delta=#{r1 - r0}"
    end)
    |> Enum.join("\n")
  end

  defp label_pid({:registered_name, name}) when name != [], do: inspect(name)
  defp label_pid({:registered_name, _}), do: "unnamed"
  defp label_pid(_), do: "unknown"

  defp cleanup(setup) do
    for pid <- setup.flooder_pids, do: send(pid, :stop)
    for {_v, client} <- setup.clients, do: :gen_tcp.close(client)

    for {_v, _port, listen_socket} <- setup.listen_sockets do
      :gen_tcp.close(listen_socket)
    end

    for pid <- setup.gcs_pids, do: Process.exit(pid, :kill)

    for name <- [MAVLink.Router, MAVLink.LocalConnection, MAVLink.ConnectionSupervisor, MAVLink.RouteTable],
        pid = Process.whereis(name),
        is_pid(pid) do
      try do
        GenServer.stop(pid, :brutal_kill)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
