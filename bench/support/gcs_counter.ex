defmodule MAVLink.Bench.GCSCounter do
  @moduledoc false

  def start_counting do
    spawn_link(fn -> loop(0) end)
  end

  defp loop(count) do
    receive do
      :get_count -> send(self(), {:count, count})
      _ -> loop(count + 1)
    after
      0 -> loop(count)
    end
  end

  def count(pid) do
    send(pid, :get_count)
    receive do
      {:count, n} -> n
    end
  end
end
