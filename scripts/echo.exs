alias MAVLink.Router, as: MAV

defmodule Echo do
  def run(count \\ 1) do
    receive do
      msg ->
        IO.puts "#{msg.source_system} -> #{msg.target_system}: #{Atom.to_string(msg.message.__struct__)}"
#        IO.inspect msg
#        if :random.uniform < 0.2 do
#          IO.puts "****** The next #{Atom.to_string(msg.__struct__)} message is a round-trip repeat of above message ******"
#          IO.inspect MAV.pack_and_send(msg)
#        end
    end
    run(count + 1)
  end
end

:observer.start
MAV.subscribe as_frame: true, target_system: 250
MAV.subscribe as_frame: true, target_system: 1
Echo.run()

