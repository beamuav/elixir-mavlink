defmodule MAVLink.SerialConnection do
  @moduledoc """
  GenServer for serial MAVLink connections.
  """

  use GenServer
  @behaviour MAVLink.Connection

  @smallest_mavlink_message 8

  require Logger

  alias MAVLink.Frame
  alias Circuits.UART
  alias MAVLink.{RouteTable, WireConnection}

  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]

  defstruct [
    :port,
    :baud,
    :uart,
    :buffer,
    :dialect,
    :connection_key,
    :test
  ]

  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:port]},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def start_test(opts) do
    GenServer.start_link(__MODULE__, Map.put(opts, :test, true))
  end

  @impl true
  def init(%{dialect: dialect, port: port, baud: baud} = opts) do
    state = %__MODULE__{
      dialect: dialect,
      port: port,
      baud: baud,
      uart: Map.get(opts, :uart),
      buffer: Map.get(opts, :buffer, <<>>),
      connection_key: Map.get(opts, :connection_key, port),
      test: Map.get(opts, :test, false)
    }

    if state.test do
      RouteTable.register_wire(self(), state.connection_key)
      {:ok, state}
    else
      send(self(), :connect)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:connect, %__MODULE__{port: port, baud: baud, uart: uart} = state) do
    if Map.has_key?(UART.enumerate(), port) do
      case UART.open(uart, port, speed: baud, active: true) do
        :ok ->
          Logger.info("Opened serial port #{port} at #{baud} baud")
          UART.controlling_process(uart, self())
          RouteTable.register_wire(self(), port)
          {:noreply, %{state | uart: uart, connection_key: port}}

        {:error, _} ->
          Logger.warn("Could not open serial port #{port}. Retrying in 1 second")
          Process.send_after(self(), :connect, 1000)
          {:noreply, state}
      end
    else
      Logger.warn("Serial port #{port} not attached. Retrying in 1 second")
      Process.send_after(self(), :connect, 1000)
      {:noreply, state}
    end
  end

  def handle_info({:circuits_uart, port, raw}, state) when is_binary(raw) do
    {:noreply, ingest({:circuits_uart, port, raw}, state)}
  end

  def handle_info({:circuits_uart, port, {:error, _reason}}, %__MODULE__{port: port, uart: uart, baud: baud} = state) do
    :ok = UART.close(uart)
    :poolboy.checkin(MAVLink.UARTPool, uart)
    uart = :poolboy.checkout(MAVLink.UARTPool)
    Process.send_after(self(), :connect, 1000)
    {:noreply, %{state | uart: uart, buffer: <<>>}}
  end

  def handle_info({:mavlink_forward_raw, packet, key}, %__MODULE__{connection_key: key, uart: uart} = state)
      when is_binary(packet) do
    UART.write(uart, packet)
    {:noreply, state}
  end

  def handle_info({:mavlink_forward, frame, key}, %__MODULE__{connection_key: key} = state) do
    forward(state, frame)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def parse_incoming({:circuits_uart, port, raw}, receiving_connection = %__MODULE__{buffer: buffer}, dialect) do
    legacy_handle_serial({:circuits_uart, port, raw}, receiving_connection, dialect)
  end

  @impl MAVLink.Connection
  def forward(%__MODULE__{uart: uart}, %Frame{version: 1, mavlink_1_raw: packet}) do
    UART.write(uart, packet)
  end

  def forward(%__MODULE__{uart: uart}, %Frame{version: 2, mavlink_2_raw: packet}) do
    UART.write(uart, packet)
  end

  defp ingest(message, state) do
    connection = to_delegate(state)

    parse_incoming(message, connection, state.dialect)
    |> WireConnection.route_result(self())
    |> from_delegate(state)
  end

  defp to_delegate(%__MODULE__{port: port, uart: uart, buffer: buffer}) do
    %__MODULE__{port: port, uart: uart, buffer: buffer}
  end

  defp from_delegate(%__MODULE__{port: port, uart: uart, buffer: buffer}, state) do
    %{state | port: port, uart: uart, buffer: buffer, connection_key: port}
  end

  defp legacy_handle_serial({:circuits_uart, port, raw}, receiving_connection = %__MODULE__{buffer: buffer}, dialect) do
    case binary_to_frame_and_tail(buffer <> raw) do
      :not_a_frame ->
        if byte_size(buffer) + byte_size(raw) > 0 do
          Logger.debug("SerialConnection.handle_info: Not a frame: #{inspect(buffer <> raw)}")
        end

        {:error, :not_a_frame, port, struct(receiving_connection, buffer: <<>>)}

      {nil, rest} ->
        {:error, :incomplete_frame, port, struct(receiving_connection, buffer: rest)}

      {received_frame, rest} ->
        if byte_size(rest) >= @smallest_mavlink_message, do: send(self(), {:circuits_uart, port, <<>>})

        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, port, struct(receiving_connection, buffer: rest), valid_frame}

          :unknown_message ->
            Logger.debug("rebroadcasting unknown message with id #{received_frame.message_id}}")

            {:ok, port, struct(receiving_connection, buffer: rest),
             struct(received_frame, target: :broadcast)}

          reason ->
            Logger.debug("SerialConnection.handle_info: frame received failed: #{Atom.to_string(reason)}")
            {:error, reason, port, struct(receiving_connection, buffer: rest)}
        end
    end
  end
end
