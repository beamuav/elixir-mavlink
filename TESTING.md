# Testing

This document covers automated tests, local integration with SITL, and
manual verification against real MAVLink traffic.

## Automated tests

The test suite starts its own `RouteTable`, `LocalConnection`, and `Router`
processes — it does **not** start the full `MAVLink.Application` supervision
tree. Run:

```bash
mix test --no-start
```

`mix test` is aliased to `--no-start` in `mix.exs`.

### What is covered

| Area | Tests |
|------|-------|
| XML parser / codegen | `mavlink_parser_test.exs`, `mavlink_task_test.exs` |
| Utils (CRC, wire order) | `mavlink_utils_test.exs` |
| Frame parse / CRC / `as_raw` path | `frame_test.exs` |
| Route table / subscriber index | `route_table_test.exs` |
| Forwarding to wire peers and subscribers | `forwarder_test.exs` |
| Router API | `router_api_test.exs`, `router_routing_test.exs` |
| Transport ingest (TCP / UDP / serial) | `connection_delegate_test.exs`, `router_transport_pipeline_test.exs` |
| Local pack and send | `local_connection_test.exs` |

Tests use a generated `TestMavlink` dialect from `test/input/test_mavlink.xml`.
On first run, `MAVLink.Test.DialectFixture` compiles `test/output/test_mavlink.ex`
via `mix mavlink`. The output file is gitignored; delete it to force regeneration.

### Test helpers

- `test/support/dialect_fixture.ex` — compile the test dialect
- `test/support/frame_fixtures.ex` — pre-built HEARTBEAT, VFR_HUD, DATA16 frames
- `test/support/router_case.ex` — shared Router/RouteTable setup for transport tests
- `test/support/connection_stubs.ex` — stub sockets and connection structs

## Generating a dialect for manual testing

Clone upstream definitions and generate a module:

```bash
git clone https://github.com/mavlink/mavlink.git ../mavlink
mix mavlink ../mavlink/message_definitions/v1.0/ardupilotmega.xml lib/apm.ex APM
```

Point your app config at the generated module:

```elixir
config :mavlink,
  dialect: APM,
  system_id: 245,
  component_id: 250,
  connections: ["tcpout:127.0.0.1:5760", "udpin:0.0.0.0:14550"]
```

## Manual testing with SITL

ArduPilot SITL exposes MAVLink on TCP port 5760 by default. A typical setup:

**Terminal 1 — SITL**

```bash
cd ardupilot/ArduCopter
sim_vehicle.py --console --map
```

**Terminal 2 — optional MAVProxy bridge to UDP**

```bash
mavproxy.py --master=tcp:127.0.0.1:5760 --out=udp:127.0.0.1:14550
```

**Terminal 3 — Elixir listener**

```bash
iex -S mix
```

```elixir
# Decoded messages
MAVLink.Router.subscribe(message: APM.Message.Heartbeat)

# Or wire bytes only (skips payload unpack when possible)
MAVLink.Router.subscribe(message: APM.Message.VfrHud, as_raw: true)

# Or full frame structs
MAVLink.Router.subscribe(as_frame: true)

defmodule Listener do
  def loop do
    receive do
      msg -> IO.inspect(msg, label: "mavlink")
    end
    loop()
  end
end

Listener.loop()
```

You should see HEARTBEAT and telemetry messages as SITL runs.

### MAVProxy noise

To suppress Emlid noise warnings in MAVProxy:

```
set shownoise False
```

Add that line to `~/.mavinit.scr` to apply on every launch.

### X-Plane + SITL

For X-Plane coupled simulation, follow the ArduPilot guide:

http://ardupilot.org/dev/docs/sitl-with-xplane.html

Use the same `tcpout:127.0.0.1:5760` connection string once SITL is listening.

## Sending messages manually

From `iex -S mix` with SITL running:

```elixir
alias APM.Message.SetMode

MAVLink.Router.pack_and_send(%SetMode{
  target_system: 1,
  base_mode: 1,
  custom_mode: 4
})
```

Replace the message and fields for your scenario. `pack_and_send/2` defaults to
MAVLink 2.

## Benchmarks

Throughput and routing benchmarks live under `bench/`. They also use
`MIX_ENV=test` and the `TestMavlink` dialect fixture.

```bash
mix benchmark.backpressure   # single TCP connection (~200k msg/s on typical hardware)
mix benchmark.fleet          # 4 vehicles × 5 GCS subscribers
mix benchmark.routing        # subscriber index lookup micro-benchmark
mix benchmark.profile        # single-connection CPU profile
mix benchmark.profile.fleet  # multi-fleet CPU profile
```

Results are written to `bench/results/`. Benchmark runs have high variance;
compare multiple runs on the same machine.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| No messages received | Connection string matches SITL/MAVProxy (`tcpout` vs `udpin`) |
| `as_raw` subscriber gets nothing | Set `config :mavlink, dialect: YourDialect` so `message_module_for/1` resolves |
| Tests fail on missing dialect | Run `mix mavlink test/input/test_mavlink.xml test/output/test_mavlink.ex TestMavlink` |
| Serial tests skipped | `circuits_uart` requires hardware; transport tests use stub sockets |

## External references

- MAVLink protocol: https://mavlink.io
- ArduPilot SITL: https://ardupilot.org/dev/docs/sitl-simulator-software-in-the-loop.html
- MAVProxy: https://ardupilot.org/mavproxy/
