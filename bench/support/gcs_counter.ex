defmodule MAVLink.Bench.GCSCounter do
  @moduledoc false

  def start_link(slot_count \\ 1) do
    counter = :atomics.new(max(slot_count, 1), signed: true)
    {:ok, counter}
  end

  def reset(counter) do
    size = :atomics.info(counter)[:size]
    reset_all(counter, size)
  end

  def reset_all(counter, slot_count) do
    for slot <- 1..slot_count, do: :atomics.put(counter, slot, 0)
    :ok
  end

  def get(counter, slot \\ 1) do
    :atomics.get(counter, slot)
  end

  def get_all(counter, slot_count) do
    for slot <- 1..slot_count, do: {slot, :atomics.get(counter, slot)}
  end

  def total(counter, slot_count) do
    Enum.reduce(1..slot_count, 0, fn slot, acc -> acc + :atomics.get(counter, slot) end)
  end

  def start_subscriber(counter, subscribe_fn) when is_function(subscribe_fn, 0) do
    start_subscriber(counter, 1, subscribe_fn)
  end

  def start_subscriber(counter, slot, subscribe_fn) when is_function(subscribe_fn, 0) and is_integer(slot) do
    parent = self()

    pid =
      spawn(fn ->
        :ok = subscribe_fn.()
        send(parent, {:gcs_subscribed, slot})
        count_loop(counter, slot)
      end)

    receive do
      {:gcs_subscribed, ^slot} -> pid
    after
      5_000 -> raise "GCS subscriber #{slot} failed to subscribe within 5s"
    end
  end

  defp count_loop(counter, slot) do
    receive do
      _ ->
        :atomics.add(counter, slot, 1)
        count_loop(counter, slot)
    end
  end
end
