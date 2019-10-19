alias MAVLink.Router, as: MAV

defmodule Echo do
  def run(count \\ 1) do
    receive do
      msg ->
        IO.puts "#{System.system_time(:second)} #{count}: #{Atom.to_string(msg.__struct__)}"
        if :random.uniform < 0.2 do
          IO.inspect MAV.pack_and_send(msg)
          IO.puts "****** The next #{Atom.to_string(msg.__struct__)} message is a round-trip repeat of above message ******"
        end
    end
    run(count + 1)
  end
end

:observer.start
MAV.subscribe #message: APM.Message.RcChannelsRaw
Echo.run()

