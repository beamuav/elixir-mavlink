defmodule MAVLink.MailboxDrain do
  @moduledoc false

  @doc """
  Drain consecutive mailbox messages of the same transport shape before returning.

  Uses selective `receive` so non-matching messages stay at the head of the queue
  for the GenServer to handle on the next turn.
  """
  @spec tcp(state :: term(), socket :: term(), ingest :: (term(), term() -> term())) :: term()
  def tcp(state, socket, ingest) when is_function(ingest, 2) do
    receive do
      {:tcp, ^socket, raw} ->
        message = {:tcp, socket, raw}
        state |> then(&ingest.(message, &1)) |> tcp(socket, ingest)
    after
      0 -> state
    end
  end

  @spec udp(state :: term(), socket :: term(), ingest :: (term(), term() -> term())) :: term()
  def udp(state, socket, ingest) when is_function(ingest, 2) do
    receive do
      {:udp, ^socket, source_addr, source_port, raw} ->
        message = {:udp, socket, source_addr, source_port, raw}
        state |> then(&ingest.(message, &1)) |> udp(socket, ingest)
    after
      0 -> state
    end
  end

  @spec circuits_uart(state :: term(), port :: term(), ingest :: (term(), term() -> term())) ::
          term()
  def circuits_uart(state, port, ingest) when is_function(ingest, 2) do
    receive do
      {:circuits_uart, ^port, raw} when is_binary(raw) ->
        message = {:circuits_uart, port, raw}
        state |> then(&ingest.(message, &1)) |> circuits_uart(port, ingest)
    after
      0 -> state
    end
  end
end
