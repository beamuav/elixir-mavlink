defmodule MAVLink.Bench.ProfileThroughput do
  @moduledoc false

  def run(opts \\ []) do
    Code.require_file("test/support/dialect_fixture.ex", File.cwd!())
    Code.require_file("test/support/frame_fixtures.ex", File.cwd!())

    alias MAVLink.Test.{DialectFixture, FrameFixtures}

    label = Keyword.get(opts, :label, "profile")
    output_file = Keyword.get(opts, :output_file, "bench/results/profile-#{label}.txt")
    port = Keyword.get(opts, :port, 15_760)
    warmup_s = Keyword.get(opts, :warmup_s, 2)
    measure_s = Keyword.get(opts, :measure_s, 5)
    dialect = DialectFixture.ensure_compiled!()
    raw = FrameFixtures.heartbeat_v2_raw(source_system: 1, source_component: 1)

    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, backlog: 1])
    setup = start_stack(dialect, port)

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

    flooder = spawn(fn -> flood_loop(client, raw) end)
    Process.sleep(warmup_s * 1000)

    profile_pids = hot_processes(setup, counter_pid, flooder)
    sampler = start_sampler(profile_pids)

    :eprof.start()
    :profiling = :eprof.start_profiling(profile_pids)

    :cprof.start()

    Agent.update(counter, fn _ -> 0 end)
    start_ms = System.monotonic_time(:millisecond)
    Process.sleep(measure_s * 1000)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms
    count = Agent.get(counter, & &1)

    :cprof.stop()
    :eprof.stop_profiling()
    eprof_report = capture_eprof()
    cprof_report = capture_cprof()
    queue_samples = stop_sampler(sampler)

    send(flooder, :stop)
    rate = if elapsed_ms > 0, do: count / (elapsed_ms / 1000), else: 0.0

    report =
      format_report(%{
        label: label,
        elapsed_ms: elapsed_ms,
        count: count,
        rate: rate,
        profile_pids: profile_pids,
        eprof_report: eprof_report,
        cprof_report: cprof_report,
        queue_samples: queue_samples,
        setup: setup
      })

    IO.puts(report)
    File.mkdir_p!("bench/results")
    File.write!(output_file, report)
    IO.puts("\nWrote #{output_file}")

    cleanup(setup, counter_pid, flooder, client, listen_socket, counter)
  end

  defp start_stack(dialect, port) do
    stack = %{dialect: dialect, port: port}

    stack =
      if Code.ensure_loaded?(MAVLink.ConnectionSupervisor) and
           function_exported?(MAVLink.ConnectionSupervisor, :start_link, 1) do
        {:ok, sup} =
          DynamicSupervisor.start_link(MAVLink.ConnectionSupervisor, [], name: MAVLink.ConnectionSupervisor)

        Map.put(stack, :connection_supervisor, sup)
      else
        stack
      end

    stack =
      if Code.ensure_loaded?(MAVLink.RouteTable) do
        {:ok, rt} = GenServer.start_link(MAVLink.RouteTable, [], name: MAVLink.RouteTable)
        Map.put(stack, :route_table, rt)
      else
        stack
      end

    stack =
      if Code.ensure_loaded?(MAVLink.LocalConnection) and
           function_exported?(MAVLink.LocalConnection, :start_link, 1) do
        {:ok, lc} =
          GenServer.start_link(
            MAVLink.LocalConnection,
            %{system: 245, component: 250, dialect: dialect},
            name: MAVLink.LocalConnection
          )

        Map.put(stack, :local_connection, lc)
      else
        stack
      end

    {:ok, router} =
      GenServer.start_link(
        MAVLink.Router,
        %{
          dialect: dialect,
          system: 245,
          component: 250,
          connection_strings: ["tcpout:127.0.0.1:#{port}"]
        },
        name: MAVLink.Router
      )

    Process.sleep(200)
    Map.put(stack, :router, router)
  end

  defp hot_processes(setup, counter_pid, flooder) do
    router = setup.router

    wire_pids =
      if Code.ensure_loaded?(MAVLink.RouteTable) do
        MAVLink.RouteTable.all_wire_peers()
        |> Enum.map(fn {pid, _} -> pid end)
        |> Enum.uniq()
      else
        []
      end

    ([router, counter_pid] ++ wire_pids)
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
    # eprof writes to stdout; capture may be empty under load but queue samples are primary signal
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
          |> Enum.sort_by(fn {_mod, _funs} -> 0 end)
          |> Enum.flat_map(fn {mod, funs} ->
            Enum.map(funs, fn {fun, arity, count} ->
              {count, mod, fun, arity}
            end)
          end)
          |> Enum.sort_by(fn {count, _, _, _} -> -count end)
          |> Enum.take(40)
          |> Enum.map(fn {count, mod, fun, arity} ->
            "#{count} #{inspect(mod)}:#{fun}/#{arity}"
          end)

        "total_calls=#{total}\n" <> Enum.join(lines, "\n")

      other ->
        inspect(other)
    end
  end

  defp format_report(opts) do
    %{
      label: label,
      elapsed_ms: elapsed_ms,
      count: count,
      rate: rate,
      profile_pids: profile_pids,
      eprof_report: eprof_report,
      cprof_report: cprof_report,
      queue_samples: queue_samples,
      setup: setup
    } = opts

    pid_lines =
      Enum.map(profile_pids, fn pid ->
        info = Process.info(pid, [:registered_name, :current_function, :message_queue_len, :reductions])
        "  #{inspect(pid)} #{inspect(info)}"
      end)

    queue_summary = summarize_queues(queue_samples, profile_pids)
    reductions_summary = summarize_reductions(queue_samples, profile_pids)

    """
    TCP throughput profile (#{label})
    Elixir #{System.version()} OTP #{System.otp_release()}
    Architecture: #{architecture_label(setup)}
    Measurement window: #{elapsed_ms} ms
    Messages received: #{count}
    Rate: #{Float.round(rate, 1)} msg/s

    Profiled processes:
    #{Enum.join(pid_lines, "\n")}

    Message queue samples (max len per process):
    #{queue_summary}

    Reductions delta over window (proxy for CPU work):
    #{reductions_summary}

    == eprof (time per function, profiled processes) ==
    #{eprof_report}

    == cprof (top call counts, whole VM) ==
    #{cprof_report}
    """
  end

  defp architecture_label(setup) do
    cond do
      Map.has_key?(setup, :connection_supervisor) -> "phase5 (per-connection GenServers)"
      Map.has_key?(setup, :route_table) -> "phase4 (ETS RouteTable + Router I/O)"
      true -> "baseline (central Router)"
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

  defp cleanup(setup, counter_pid, flooder, client, listen_socket, counter) do
    Process.exit(counter_pid, :kill)
    Process.exit(flooder, :kill)
    :gen_tcp.close(client)
    :gen_tcp.close(listen_socket)

    for key <- [:router, :local_connection, :route_table, :connection_supervisor],
        pid = Map.get(setup, key),
        is_pid(pid) do
      try do
        GenServer.stop(pid, :normal, 1_000)
      catch
        :exit, _ -> :ok
      end
    end

    try do
      GenServer.stop(counter, :normal, 1_000)
    catch
      :exit, _ -> :ok
    end
  end
end
