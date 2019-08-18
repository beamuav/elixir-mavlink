defmodule Mix.Tasks.Compile.Mavlink do
  use Mix.Task

  def run(_args) do
    HTTPoison.start()

    %HTTPoison.Response{body: body} = HTTPoison.get!("https://raw.githubusercontent.com/ArduPilot/mavlink/1.0.12/message_definitions/v1.0/common.xml")
    File.write!("message_definitions/v1.0/common.xml", body) 

    %HTTPoison.Response{body: body} = HTTPoison.get!("https://raw.githubusercontent.com/ArduPilot/mavlink/1.0.12/message_definitions/v1.0/uAvionix.xml")
    File.write!("message_definitions/v1.0/uAvionix.xml", body) 

    %HTTPoison.Response{body: body} = HTTPoison.get!("https://raw.githubusercontent.com/ArduPilot/mavlink/1.0.12/message_definitions/v1.0/icarous.xml")
    File.write!("message_definitions/v1.0/icarous.xml", body) 

    %HTTPoison.Response{body: body} = HTTPoison.get!("https://raw.githubusercontent.com/ArduPilot/mavlink/1.0.12/message_definitions/v1.0/ardupilotmega.xml")
    File.write!("message_definitions/v1.0/ardupilotmega.xml", body) 

    MAVLink.Generator.generate!("message_definitions/v1.0/ardupilotmega.xml", "lib/mavlink/dialect/apm.ex", "MAVLink.Dialect.APM")
    :ok
  end
end
