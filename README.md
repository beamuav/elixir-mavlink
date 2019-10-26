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
     {:mavlink, "~> 0.5.0"}
   ]
 end
 ```

## Current Status

![](https://github.com/beamuav/elixir-mavlink/workflows/Elixir/badge.svg)

This library is not officially recognised or supported by MAVLink at this
time. We aim over time to achieve complete compliance with the MAVLink 2.0
specification, but our initial focus is on using this library on companion
computers and ground stations for our team entry in the 
2020 UAV Outback Challenge https://uavchallenge.org/medical-rescue/.
