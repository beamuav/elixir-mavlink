alias MAVLink.Router, as: MAV

defmodule Echo do
  def run() do
    receive do
      msg ->
        IO.inspect msg
        if :random.uniform < 0.2 do
          IO.inspect MAV.pack_and_send(msg)
          IO.puts "****** The next #{Atom.to_string(msg.__struct__)} message is a round-trip repeat of above message ******"
        end
    end
    run()
  end
end

:observer.start
MAV.subscribe #message: APM.Message.RcChannelsRaw
Echo.run()

