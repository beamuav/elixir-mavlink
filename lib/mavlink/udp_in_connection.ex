defmodule MAVLink.UDPInConnection do
  @moduledoc """
  GenServer for inbound UDP MAVLink listen sockets.
  """

  use GenServer
  @behaviour MAVLink.Connection

  require Logger

  alias MAVLink.Frame
  alias MAVLink.{MailboxDrain, RouteTable, WireConnection}

  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]

  defstruct [
    :listen_address,
    :listen_port,
    :address,
    :port,
    :socket,
    :dialect,
    :clients,
    :test,
    :active_n
  ]

  def child_spec(opts) do
    %{
      id: {__MODULE__, {opts[:listen_address], opts[:listen_port]}},
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
  def init(%{dialect: dialect, listen_address: address, listen_port: port} = opts) do
    active = Map.get(opts, :active, @default_active)

    state = %__MODULE__{
      dialect: dialect,
      listen_address: address,
      listen_port: port,
      socket: Map.get(opts, :socket),
      clients: Map.get(opts, :clients, %{}),
      test: Map.get(opts, :test, false),
      active_n: active
    }

    if state.test do
      {:ok, state}
    else
      send(self(), :connect)
      {:ok, state}
    end
  end

  @impl true
  def handle_info(:connect, %__MODULE__{listen_address: address, listen_port: port, active_n: active} = state) do
    case :gen_udp.open(port, [:binary, {:ip, address}, {:active, active}]) do
      {:ok, socket} ->
        Logger.info("Opened udpin:#{Enum.join(Tuple.to_list(address), ".")}:#{port}")
        {:noreply, %{state | socket: socket}}

      other ->
        Logger.warn(
          "Could not open udpin:#{Enum.join(Tuple.to_list(address), ".")}:#{port}: #{inspect(other)}. Retrying in 1 second"
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

  def handle_info({:mavlink_forward_raw, packet, key}, state) when is_binary(packet) do
    case Map.get(state.clients, key) do
      %__MODULE__{socket: socket, address: address, port: port} ->
        :gen_udp.send(socket, address, port, packet)

      nil ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:mavlink_forward, frame, key}, state) do
    case Map.get(state.clients, key) do
      nil -> :ok
      client -> forward(client, frame)
    end

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
    key = connection_key(message)

    connection =
      case {key, Map.get(state.clients, key)} do
        {_, %__MODULE__{} = client} -> client
        {key, nil} when not is_nil(key) -> %__MODULE__{socket: elem(key, 0), address: elem(key, 1), port: elem(key, 2)}
        _ -> nil
      end

    case parse_incoming(message, connection, state.dialect) do
      {:ok, client_key, client, frame} ->
        RouteTable.register_wire(self(), client_key)
        client = struct(client, address: client.address, port: client.port, socket: client.socket)
        WireConnection.route_result({:ok, client_key, client, frame}, self())
        %{state | clients: Map.put(state.clients, client_key, client)}

      {:error, _reason, client_key, client} when not is_nil(client_key) ->
        %{state | clients: Map.put(state.clients, client_key, client)}

      {:error, _reason, _client_key, _client} ->
        state
    end
  end

  defp connection_key({:udp, socket, source_addr, source_port, _raw}),
    do: {socket, source_addr, source_port}

  defp rearm_socket(%__MODULE__{test: true} = state), do: state

  defp rearm_socket(%__MODULE__{socket: socket, active_n: active} = state) when is_port(socket) do
    :inet.setopts(socket, [{:active, active}])
    state
  end

  defp rearm_socket(state), do: state

  defp legacy_handle_udp({:udp, socket, source_addr, source_port, raw}, receiving_connection, dialect) do
    case binary_to_frame_and_tail(raw) do
      :not_a_frame ->
        Logger.debug("UDPInConnection.handle_info: Not a frame #{inspect(raw)}")
        {:error, :not_a_frame, {socket, source_addr, source_port}, receiving_connection}

      {received_frame, _rest} ->
        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, {socket, source_addr, source_port}, receiving_connection, valid_frame}

          :unknown_message ->
            Logger.debug("rebroadcasting unknown message with id #{received_frame.message_id}}")

            {:ok, {socket, source_addr, source_port}, receiving_connection,
             struct(received_frame, target: :broadcast)}

          reason ->
            Logger.debug(
              "UDPInConnection.handle_info: frame received from " <>
                "#{Enum.join(Tuple.to_list(source_addr), ".")}:#{source_port} failed: #{Atom.to_string(reason)}"
            )

            {:error, reason, {socket, source_addr, source_port}, receiving_connection}
        end
    end
  end
end
