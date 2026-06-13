# MAVLink

This library includes a Mix task that generates code from MAVLink XML
definition files and an application that routes MAVLink 1.0 and 2.0 traffic
over serial, UDP, and TCP connections.

MAVLink is a micro air vehicle communication protocol used by Pixhawk,
ArduPilot, and other autopilot platforms. For more information see
https://mavlink.io.

## Installation

If [available in Hex](https://hex.pm/docs/publish), add `mavlink` to your
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mavlink, "~> 0.9.0"}
  ]
end
```

## Current Status

![](https://github.com/beamuav/elixir-mavlink/workflows/Elixir/badge.svg)

This library is not officially recognised or supported by MAVLink. The focus
is practical routing and dialect support for companion computers and ground
stations. MAVLink 2 signing is not implemented yet.

Requires Elixir ~> 1.14.

## Generating MAVLink Dialect Modules

MAVLink message definition files for popular dialects can be found
[here](https://github.com/mavlink/mavlink/tree/master/message_definitions/v1.0).

To generate an Elixir module for a dialect (for example `ardupilotmega`):

```bash
mix mavlink path/to/ardupilotmega.xml lib/apm.ex APM
```

The generated dialect module provides:

- `msg_attributes/1` — CRC extra, payload size, and target type per message id
- `message_module_for/1` — message struct module for a message id
- `unpack/3` — decode a payload into a message struct
- per-message modules implementing `MAVLink.Message` for packing

Array fields are unpacked with bitstring comprehensions at code generation
time.

## Configuring the Application

Add `:mavlink` to your application list and configure the dialect, local
system/component ids, and connection strings in `config.exs`:

```elixir
config :mavlink,
  dialect: APM,
  system_id: 245,
  component_id: 250,
  connections: [
    "serial:/dev/cu.usbserial-A603KH3Y:57600",
    "udpin:0.0.0.0:14550",
    "udpout:127.0.0.1:14550",
    "tcpout:127.0.0.1:5760"
  ]
```

| Key | Description |
|-----|-------------|
| `:dialect` | Generated dialect module (required) |
| `:system_id` | MAVLink system id used when packing local messages (default `245`) |
| `:component_id` | MAVLink component id used when packing local messages (default `250`) |
| `:connections` | List of connection strings (default `[]`) |

### Connection strings

Connection strings use the form `protocol:host:port` or `protocol:device:baud`.

| Protocol | Role | Example |
|----------|------|---------|
| `serial` | Local UART | `serial:/dev/ttyUSB0:57600` |
| `udpin` | UDP server (listen) | `udpin:0.0.0.0:14550` |
| `udpout` | UDP client (send to) | `udpout:127.0.0.1:14550` |
| `tcpout` | TCP client (typical SITL) | `tcpout:127.0.0.1:5760` |

`in` means listen/server; `out` means connect/client.

On startup the application supervises:

- `MAVLink.RouteTable` — routes, wire peers, and subscriber index
- `MAVLink.ConnectionSupervisor` — one GenServer per configured connection
- `MAVLink.LocalConnection` — packs and injects locally originated messages
- `MAVLink.Router` — public API facade

Failed connections retry every second. Subscriber registrations are cached and
restored across `RouteTable` restarts; crashed subscriber processes are
removed automatically.

## Receiving MAVLink Messages

Subscribe from any process. Matching messages are delivered directly to the
subscriber's mailbox.

```elixir
alias MAVLink.Router, as: MAV

# Decoded message struct (default)
:ok = MAV.subscribe(message: APM.Message.Heartbeat, source_system: 1)

# Full frame struct (includes metadata and raw bytes)
:ok = MAV.subscribe(as_frame: true)

# Wire bytes only — skips payload unpack when possible
:ok = MAV.subscribe(message: APM.Message.VfrHud, as_raw: true)

receive do
  %APM.Message.Heartbeat{} = msg ->
    IO.inspect(msg)

  %MAVLink.Frame{} = frame ->
    IO.inspect(frame)

  <<0xFD, _::binary>> = raw ->
    IO.puts("received #{byte_size(raw)} raw bytes")
end
```

### Subscribe filters

All filters default to wildcard (`0` for ids, `nil` for message type).

| Option | Description |
|--------|-------------|
| `:message` | Message module atom, e.g. `APM.Message.Heartbeat` |
| `:source_system` | Filter by sender system id |
| `:source_component` | Filter by sender component id |
| `:target_system` | Filter by target system id (non-broadcast messages) |
| `:target_component` | Filter by target component id |
| `:as_frame` | Deliver `%MAVLink.Frame{}` instead of the message struct |
| `:as_raw` | Deliver `mavlink_1_raw` / `mavlink_2_raw` wire bytes |

`:as_raw` and decoded delivery are mutually exclusive in practice — when
`as_raw: true`, the router validates the checksum and routes using header
fields and `message_module_for/1` without unpacking the payload.

Call `MAVLink.Router.unsubscribe/0` from the subscribing process to remove
its subscription.

## Sending MAVLink Messages

```elixir
alias MAVLink.Router, as: MAV
alias APM.Message.RcChannelsOverride

:ok =
  MAV.pack_and_send(
    %RcChannelsOverride{
      target_system: 1,
      target_component: 1,
      chan1_raw: 1500,
      chan2_raw: 1500,
      chan3_raw: 1500,
      chan4_raw: 1500,
      chan5_raw: 1500,
      chan6_raw: 1500,
      chan7_raw: 1500,
      chan8_raw: 1500,
      chan9_raw: 0,
      chan10_raw: 0,
      chan11_raw: 0,
      chan12_raw: 0,
      chan13_raw: 0,
      chan14_raw: 0,
      chan15_raw: 0,
      chan16_raw: 0,
      chan17_raw: 0,
      chan18_raw: 0
    }
  )
```

`pack_and_send/2` defaults to MAVLink 2. Outgoing frames are routed to wire
peers and local subscribers the same way as received traffic.

## Router Architecture

The router is to Elixir processes what
[MAVProxy](https://ardupilot.org/mavproxy/) is to Python modules: a central
switch that gives your code access to other MAVLink systems. Unlike MAVProxy
it does not start or schedule your application logic.

```
Connection GenServers (serial / udpin / udpout / tcpout)
  → parse frame (binary_to_frame_and_tail)
  → prepare_for_route (checksum; unpack only when needed)
  → Forwarder.route/3
       ├─ wire peers: forward raw packet or frame
       └─ subscribers: deliver struct, frame, or raw bytes
```

Key modules:

| Module | Role |
|--------|------|
| `MAVLink.Router` | Public API: subscribe, unsubscribe, pack_and_send |
| `MAVLink.RouteTable` | ETS-backed routes, wire-peer registry, indexed subscribers |
| `MAVLink.Forwarder` | Route a validated frame to wire peers and subscribers |
| `MAVLink.Frame` | Frame parse/pack, binary CRC, conditional unpack |
| `MAVLink.*Connection` | Per-link I/O GenServers with mailbox draining |

Wire peers learn source addresses from incoming traffic (`RouteTable.put_route/2`)
so targeted messages can be forwarded back to the correct link.

## Benchmarks

Throughput and routing micro-benchmarks live under `bench/`. Useful Mix
aliases:

```bash
mix benchmark.backpressure   # single TCP connection throughput
mix benchmark.fleet          # multi-vehicle / multi-GCS scenario
mix benchmark.routing          # subscriber lookup micro-benchmark
```

Run with `MIX_ENV=test` (see `mix.exs` aliases). Results are written to
`bench/results/`.

## Roadmap

- MAVLink microservice/protocol helpers (see [elixir_mavlink_util](https://github.com/beamuav/elixir_mavlink_util))
- Signed MAVLink v2 messages
