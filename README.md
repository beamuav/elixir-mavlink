# MAVLink

This library includes a mix task that generates code from a MAVLink xml
definition files and an application that enables communication with other
systems using the MAVLink 1.0 or 2.0 protocol over serial, UDP and TCP
connections.

MAVLink is a Micro Air Vehicle communication protocol used by Pixhawk, 
Ardupilot and other leading autopilot platforms. For more information
on MAVLink see https://mavlink.io.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mavlink` to your list of dependencies in `mix.exs`:

  ```elixir
 def deps do
   [
     {:mavlink, "~> 0.6.0"}
   ]
 end
 ```

## Current Status

![](https://github.com/beamuav/elixir-mavlink/workflows/Elixir/badge.svg)

This library is not officially recognised or supported by MAVLink at this
time. We aim over time to achieve complete compliance with the MAVLink 2.0
specification, but our initial focus is on using this library on companion
computers and ground stations for our team entry in the 
[2020 UAV Outback Challenge](https://uavchallenge.org/medical-rescue/).

## Generating MAVLink Dialect Modules
MAVLink message definition files for popular dialects can be found [here](https://github.com/mavlink/mavlink/tree/master/message_definitions/v1.0).
To generate an Elixir source file containing the modules we need to speak a MAVLink dialect (for example ardupilotmega):

```
> mix mavlink test/input/ardupilotmega.xml lib/apm.ex APM
* creating lib/apm.ex
Generated APM in 'lib/apm.ex'.
>
```

## Configuring the MAVLink Application
Add `MAVLink.Application` with no start arguments to your `mix.exs`. You need to point the application at the dialect you just generated 
and list the connections to other vehicles in `config.exs`:

```
config :mavlink, dialect: APM, connections: ["udpout:127.0.0.1:14550", "tcpout:127.0.0.1:5760"]
```

The above config specifies the APM dialect we generated and connects to a ground station listening for 
UDP packets on 14550 and a SITL vehicle listening for TCP connections on 5760. Remember 'out' means client, 
'in' means server.

## Receive MAVLink messages
With the configured MAVLink application running you can subscribe to particular MAVLink messages:

```
alias MAVLink.Router, as: MAV

defmodule Echo do
  def run() do
    receive do
      msg ->
        IO.inspect msg
    end
    run()
  end
end

MAV.subscribe source_system: 1, message: APM.Message.Heartbeat
Echo.run()
```

or send a MAVLink message:

```
alias MAVLink.Router, as: MAV
alias APM.Message.RcChannelsOverride

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

## Roadmap
- Serial Connections
- Reconnect dropped connections
- Resubscribe subscribing processes on router restart
- MAVLink microservice/protocol helpers
- Signed MAVLink v2 messages
