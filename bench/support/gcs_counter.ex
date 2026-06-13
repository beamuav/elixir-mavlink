defmodule MAVLink.Bench.GCSCounter do
  @moduledoc false

  def start_link do
    counter = :atomics.new(1, signed: true)
    {:ok, counter}
  end

  def reset(counter) do
    :atomics.put(counter, 1, 0)
    :ok
  end

  def get(counter) do
    :atomics.get(counter, 1)
  end

  def start_subscriber(counter, subscribe_fn) when is_function(subscribe_fn, 0) do
    spawn(fn ->
      :ok = subscribe_fn.()
      count_loop(counter)
    end)
  end

  defp count_loop(counter) do
    receive do
      _ ->
        :atomics.add(counter, 1, 1)
        count_loop(counter)
    end
  end
end
