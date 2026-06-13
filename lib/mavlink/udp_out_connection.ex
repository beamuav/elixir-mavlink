defmodule MAVLink.UDPOutConnection do
  @moduledoc """
  GenServer for outbound UDP MAVLink connections.
  """

  use GenServer
  @behaviour MAVLink.Connection

  require Logger

  alias MAVLink.Frame
  alias MAVLink.{MailboxDrain, RouteTable, WireConnection}

  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, prepare_for_route: 2]

  defstruct [
    :address,
    :port,
    :socket,
    :dialect,
    :connection_key,
    :test,
    :active_n
  ]

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
    case :gen_udp.open(0, [:binary, {:active, active}]) do
      {:ok, socket} ->
        Logger.info("Opened udpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}")
        RouteTable.register_wire(self(), socket)
        {:noreply, %{state | socket: socket, connection_key: socket}}

      other ->
        Logger.debug(
          "Could not open udpout:#{Enum.join(Tuple.to_list(address), ".")}:#{port}: #{inspect(other)}. Retrying in 1 second"
        )

        Process.send_after(self(), :connect, 1000)
        {:noreply, state}
    end
  end

  def handle_info({:udp, socket, source_addr, source_port, raw}, state) do
    message = {:udp, socket, source_addr, source_port, raw}

    new_state =
      state
      |> then(&ingest(message, &1))
      |> MailboxDrain.udp(socket, &ingest/2)
      |> rearm_socket()

    {:noreply, new_state}
  end

  def handle_info({:mavlink_forward_raw, packet, key}, %__MODULE__{connection_key: key} = state)
      when is_binary(packet) do
    :gen_udp.send(state.socket, state.address, state.port, packet)
    {:noreply, state}
  end

  def handle_info({:mavlink_forward, frame, key}, %__MODULE__{connection_key: key} = state) do
    forward(state, frame)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  def parse_incoming({:udp, socket, source_addr, source_port, raw}, nil, dialect) do
    parse_incoming(
      {:udp, socket, source_addr, source_port, raw},
      %__MODULE__{address: source_addr, port: source_port, socket: socket},
      dialect
    )
  end

  def parse_incoming({:udp, socket, source_addr, source_port, raw}, receiving_connection, dialect) do
    legacy_handle_udp({:udp, socket, source_addr, source_port, raw}, receiving_connection, dialect)
  end

  @impl MAVLink.Connection
  def forward(%__MODULE__{socket: socket, address: address, port: port}, %Frame{version: 1, mavlink_1_raw: packet}) do
    :gen_udp.send(socket, address, port, packet)
  end

  def forward(%__MODULE__{socket: socket, address: address, port: port}, %Frame{version: 2, mavlink_2_raw: packet}) do
    :gen_udp.send(socket, address, port, packet)
  end

  defp ingest(message, state) do
    connection = to_delegate(state)

    parse_incoming(message, connection, state.dialect)
    |> WireConnection.route_result(self())
    |> from_delegate(state)
  end

  defp to_delegate(%__MODULE__{socket: socket, address: address, port: port}) do
    %__MODULE__{socket: socket, address: address, port: port}
  end

  defp from_delegate(%__MODULE__{socket: socket, address: address, port: port}, state) do
    key = socket || state.connection_key

    if key && key != state.connection_key do
      RouteTable.register_wire(self(), key)
    end

    %{state | socket: socket, address: address, port: port, connection_key: key || state.connection_key}
  end

  defp rearm_socket(%__MODULE__{test: true} = state), do: state

  defp rearm_socket(%__MODULE__{socket: socket, active_n: active} = state) when is_port(socket) do
    :inet.setopts(socket, [{:active, active}])
    state
  end

  defp rearm_socket(state), do: state

  defp legacy_handle_udp({:udp, socket, source_addr, source_port, raw}, receiving_connection, dialect) do
    case binary_to_frame_and_tail(raw) do
      :not_a_frame ->
        Logger.debug("UDPOutConnection.handle_info: Not a frame #{inspect(raw)}")
        {:error, :not_a_frame, {socket, source_addr, source_port}, receiving_connection}

      {received_frame, _rest} ->
        case prepare_for_route(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, {socket, source_addr, source_port}, receiving_connection, valid_frame}

          :unknown_message ->
            Logger.debug("relaying unknown message with id #{received_frame.message_id}}")

            {:ok, {socket, source_addr, source_port}, receiving_connection,
             struct(received_frame, target: :broadcast)}

          reason ->
            Logger.debug(
              "UDPOutConnection.handle_info: frame received from " <>
                "#{Enum.join(Tuple.to_list(source_addr), ".")}:#{source_port} failed: #{Atom.to_string(reason)}"
            )

            {:error, reason, {socket, source_addr, source_port}, receiving_connection}
        end
    end
  end
end
