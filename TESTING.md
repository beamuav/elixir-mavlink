# Testing locally with Ardupilot, MavProxy, SITL and X-Plane

It's possible to use SITL with X-Plane:

http://ardupilot.org/dev/docs/sitl-with-xplane.html

### Install dependencies:

<!-- Install Python 3:

```
brew install python
``` -->

Ensure the above version overrides the built-in Python 2 in macOS, by adding this
to the end of your `.zshrc` or `.bash_profile`:

```
export PATH="/usr/local/opt/python/libexec/bin:$PATH"
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

```
git clone git@github.com:ArduPilot/ardupilot.git
```

Build Ardupilot for macOS:

```
brew uninstall binutils
cd ardupilot
./Tools/environment_install/install-prereqs-mac.sh
```

Configure Ardupilot for SITL:

./waf configure --board sitl

And run Arducopter:

```bash
cd ardupilot/ArduCopter
cd ArduCopter
sim_vehicle.py -w
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
git clone  git@github.com:mavlink/mavlink.git
cd elixir-mavlink
```

The message definitions live in:

```
message_definitions/v1.0
```

To generate a protocol file for APM:

```bash
mkdir message_definitions
cp ../mavlink/message_definitions/v1.0/\* message_definitions

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