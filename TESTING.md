# Testing locally with Ardupilot, MavProxy, SITL and X-Plane

It's possible to use SITL with X-Plane:

http://ardupilot.org/dev/docs/sitl-with-xplane.html

### Install dependencies:

```
brew install python@2.7
```

Verify with: `python --version`.

Remove this incompatible library:

```
sudo pip uninstall python-dateutil
```

### Install MavProxy

```
sudo pip install wxPython
sudo pip install gnureadline
sudo pip install billiard
sudo pip install numpy pyparsing
sudo pip install MAVProxy
```

### Ardupilot

Install Ardupilot dependencies:

```
brew tap ardupilot/homebrew-px4
brew install genromfs
brew install gcc-arm-none-eabi
brew install gawk
```

Download Ardupilot:

```bash
git clone git@github.com:ArduPilot/ardupilot.git
```

Build Ardupilot for macOS:

```bash
cd ardupilot && ./Tools/environment_install/install-prereqs-mac.sh
```

Add the following to your shell:

```
export PATH=/Path/To/ardupilot/Tools/autotest:$PATH
```

Configure Ardupilot for SITL:

```
cd ardupilot
./waf configure --board sitl
cd ArduCopter
sim_vehicle.py -w
```

After initialisation Ctl C and run the following:

```
sim_vehicle.py --console
```

Start X-Plane and set up the data export settings per web page, then run arduplane and mavproxy

mavproxy.py --master=tcp:127.0.0.1:5760 --out 127.0.0.1:14550

Then

```bash
mix run scripts/listen.exs
```

will receive messages

## to kill emlid noise bug in mavproxy:

```
set shownoise False
```

Which can also be added to `~/.mavinit.scr` to run every time `mavproxy.py` runs.

# Testing against real message definition files

In another directory (like `..`):

```bash
git clone git@github.com:mavlink/mavlink.git
cd elixir-mavlink
```

The message definitions live in:

```
message_definitions/v1.0
```

To generate a protocol file for APM:

```bash
mkdir message_definitions
cp ../mavlink/message_definitions/v1.0/* message_definitions
mix mavlink message_definitions/ardupilotmega.xml output/apm.ex APM
```

## Example usage

```elixir
defmodule TestLog do
  def start do
    MAVLink.Router.subscribe(message: APM.Message.VfrHud)
    # MAVLink.Router.subscribe(message: APM.Message.SysStatus)
    # MAVLink.Router.subscribe(message: APM.Message.Heartbeat)
    # MAVLink.Router.subscribe(message: APM.Message.GlobalPositionInt)
    loop()
  end

  def loop do
    receive do
      x ->
        IO.inspect(x)
        loop()
    end
  end
end

TestLog.start()
```
