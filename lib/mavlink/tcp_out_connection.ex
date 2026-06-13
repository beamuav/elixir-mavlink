defmodule MAVLink.TCPOutConnection do
  @moduledoc """
  GenServer for outbound TCP MAVLink connections (typically SITL on port 5760).
  """

  use GenServer
  @behaviour MAVLink.Connection

  @smallest_mavlink_message 8

  require Logger

  alias MAVLink.Frame
  alias MAVLink.{RouteTable, WireConnection}

  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]

  defstruct [
    :socket,
    :address,
    :port,
    :buffer,
    :dialect,
    :connection_key,
    :test,
    :active_n
  ]

  @type t :: %__MODULE__{
          socket: port() | nil,
          address: MAVLink.Types.net_address(),
          port: MAVLink.Types.net_port(),
          buffer: binary(),
          dialect: module() | nil,
          connection_key: term(),
          test: boolean()
        }

  def child_spec(opts) do
    %{
      id: {__MODULE__, {opts[:address], opts[:port]}},
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

  @default_active :once

  @impl true
  def init(%{dialect: dialect, address: address, port: port} = opts) do
    active = Map.get(opts, :active, @default_active)

    state = %__MODULE__{
      dialect: dialect,
      address: address,
      port: port,
      buffer: Map.get(opts, :buffer, <<>>),
      socket: Map.get(opts, :socket),
      connection_key: Map.get(opts, :connection_key),
      test: Map.get(opts, :test, false),
      active_n: active
    }

    if state.test do
      key = state.connection_key || state.socket
      RouteTable.register_wire(self(), key)
      {:ok, %{state | connection_key: key}}
    else
      send(self(), :connect)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:connect, %__MODULE__{address: address, port: port, active_n: active} = state) do
    case :gen_tcp.connect(address, port, [:binary, {:active, active}]) do
      {:ok, socket} ->
        Logger.debug("Opened tcpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}")
        RouteTable.register_wire(self(), socket)
        {:noreply, %{state | socket: socket, connection_key: socket, buffer: <<>>}}

      other ->
        Logger.debug(
          "Could not open tcpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}: #{inspect(other)}. Retrying in 1 second"
        )

        Process.send_after(self(), :connect, 1000)
        {:noreply, state}
    end
  end

  def handle_info({:tcp_closed, socket}, %__MODULE__{socket: socket} = state) do
    Process.send_after(self(), :connect, 1000)
    {:noreply, %{state | socket: nil, buffer: <<>>}}
  end

  def handle_info({:tcp, socket, raw}, state) do
    new_state =
      state
      |> then(&ingest({:tcp, socket, raw}, &1))
      |> rearm_socket()

    {:noreply, new_state}
  end

  def handle_info({:mavlink_forward_raw, packet, key}, %__MODULE__{socket: socket, connection_key: key} = state)
      when is_binary(packet) and not is_nil(socket) do
    :gen_tcp.send(socket, packet)
    {:noreply, state}
  end

  def handle_info({:mavlink_forward, frame, key}, %__MODULE__{connection_key: key} = state) do
    forward(state, frame)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Delegate API retained for unit tests
  def parse_incoming({:tcp, socket, raw}, %__MODULE__{} = receiving_connection, dialect) do
    legacy_handle_tcp({:tcp, socket, raw}, receiving_connection, dialect)
  end

  @impl MAVLink.Connection
  def forward(%__MODULE__{socket: socket}, %Frame{version: 1, mavlink_1_raw: packet}) do
    :gen_tcp.send(socket, packet)
  end

  def forward(%__MODULE__{socket: socket}, %Frame{version: 2, mavlink_2_raw: packet}) do
    :gen_tcp.send(socket, packet)
  end

  defp ingest(message, state) do
    connection = to_delegate(state)

    parse_incoming(message, connection, state.dialect)
    |> WireConnection.route_result(self())
    |> from_delegate(state)
  end

  defp to_delegate(%__MODULE__{socket: socket, buffer: buffer}) do
    %__MODULE__{socket: socket, buffer: buffer}
  end

  defp from_delegate(%__MODULE__{socket: socket, buffer: buffer}, state) do
    %{state | socket: socket, buffer: buffer, connection_key: socket || state.connection_key}
  end

  defp rearm_socket(%__MODULE__{test: true} = state), do: state

  defp rearm_socket(%__MODULE__{socket: socket, active_n: active} = state) when is_port(socket) do
    :inet.setopts(socket, [{:active, active}])
    state
  end

  defp rearm_socket(state), do: state

  defp legacy_handle_tcp({:tcp, socket, raw}, receiving_connection = %__MODULE__{buffer: buffer}, dialect) do
    case binary_to_frame_and_tail(buffer <> raw) do
      :not_a_frame ->
        if byte_size(buffer) + byte_size(raw) > 0 do
          Logger.debug("TCPOutConnection.handle_info: Not a frame #{inspect(buffer <> raw)}")
        end

        {:error, :not_a_frame, socket, struct(receiving_connection, buffer: <<>>)}

      {nil, rest} ->
        {:error, :incomplete_frame, socket, struct(receiving_connection, buffer: rest)}

      {received_frame, rest} ->
        if byte_size(rest) >= @smallest_mavlink_message, do: send(self(), {:tcp, socket, <<>>})

        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, socket, struct(receiving_connection, buffer: rest), valid_frame}

          :unknown_message ->
            Logger.debug("rebroadcasting unknown message with id #{received_frame.message_id}}")

            {:ok, socket, struct(receiving_connection, buffer: rest),
             struct(received_frame, target: :broadcast)}

          reason ->
            Logger.debug(
              "TCPOutConnection.handle_info: frame received failed: #{Atom.to_string(reason)}"
            )

            {:error, reason, socket, struct(receiving_connection, buffer: rest)}
        end
    end
  end
end
