# MAVLink

MAVLink is a Micro Air Vehicle communication protocol used by Pixhawk, 
Ardupilot and other leading autopilot platforms. For more information
on MAVLink see https://mavlink.io.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `mavlink` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mavlink, "~> 0.2.0"}
  ]
end
```

## Current Status

This library is not officially recognised or supported by MAVLink at this
time. We aim over time to achieve complete compliance with the MAVLink 2.0
specification, but our initial focus is on using this library on companion
computers and ground stations for our team entry in the 
2020 UAV Outback Challenge https://uavchallenge.org/medical-rescue/.

## Contributing

A Mix task to generate code from a MAVLink xml definition file, and an 
application that enables communication with other systems using the 
MAVLink 1.0 or 2.0 protocol over serial, UDP and TCP connections.

```
mix build
```
