defmodule MAVLink.Router do
  @moduledoc """
  Connect to serial, udp and tcp ports and listen for, validate and
  forward MAVLink messages towards their destinations on other connections
  and/or Elixir processes subscribing to messages.
  
  The rules for MAVLink packet forwarding are described here:
  
    https://mavlink.io/en/guide/routing.html
  
  and here:
  
    http://ardupilot.org/dev/docs/mavlink-routing-in-ardupilot.html
  """
  
  use GenServer
  
  alias Circuits.UART, as: UART
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1, x25_crc: 1, x25_crc: 2]
  
  
  # Client API
  
  
  def start_link(state, opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      state,
      [{:name, __MODULE__} | opts])
  end
  
  
  @doc """
  Not recommended to create connections at runtime. You should set
  connection strings through config.exs so that the supervisor can
  re-establish connections if the router crashes.
  """
  def connect(connection_string) do
    GenServer.call __MODULE__, {:connect, connection_string}
  end
  
  
  # Callbacks

  # TODO refactor init, lacks elegance...
  
  @impl true
  def init(state = %{dialect: dialect, connections: []}) do
    if dialect == nil do
      IO.puts "WARNING: No MAVLink dialect module specified in config.exs."
    end
    {
      :ok,
      Map.merge(
        state,
        %{
          conn_details: %{},      # serial or network connection
          targets: %{},           # systems and components
          subscriptions: %{}      # local PIDs
        }
      )
    }
  end
  
  def init(state = %{dialect: dialect, connections: [_ | _]}) do
    if dialect == nil do
      IO.puts "WARNING: No MAVLink dialect module specified in config.exs."
    end
    {
      :ok,
      state.connections |> Enum.reduce(
        Map.merge(
          state,
          %{
            conn_details: %{},      # serial or network connection
            targets: %{},           # systems and components
            subscriptions: %{}      # local PIDs
          }
        ),
        fn connection_string, acc_state ->
          {:reply, :ok, next_acc_state} = String.split(connection_string, [":", ","]) |> do_connect(acc_state)
          next_acc_state
        end
      )
    }
  end
  
  
  @impl true
  def handle_call({:connect, connection_string}, _from, state) do
    String.split(connection_string, [":", ","]) |> do_connect(state)
  end

  
  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end
  
  
  @doc """
  Respond to incoming messages from connections
  """
  @impl true
  def handle_info({:udp, _sock, addr, port, raw=
    <<0xfe, # MAVLink version 1
      payload_length::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system_id::unsigned-integer-size(8),
      source_component_id::unsigned-integer-size(8),
      message_id::unsigned-integer-size(8),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do

    {:noreply, state |> validate_and_route_message_frame(
        1, {:udp, addr, port}, raw, payload_length, sequence_number,
        source_system_id, source_component_id, message_id,
        payload, checksum)}
  end
  
  def handle_info({:udp, _sock, addr, port, raw=
    <<0xfd, # MAVLink version 2
      payload_length::unsigned-integer-size(8),
      0::unsigned-integer-size(8),   # TODO Rejecting all incompatible flags for now
      _compatible_flags::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      source_system_id::unsigned-integer-size(8),
      source_component_id::unsigned-integer-size(8),
      message_id::little-unsigned-integer-size(24),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do

    {:noreply, state |> validate_and_route_message_frame(
        2, {:udp, addr, port}, raw, payload_length, sequence_number,
        source_system_id, source_component_id, message_id,
        payload, checksum)}
  end
  
  def handle_info({:udp, _sock, _addr, _port, _}, state) do
    # Ignore packets we don't recognise
    {:noreply, state}
  end
  
  # TODO TCP and serial (will need to consume up to marker in buffer)
  
  
  # Helpers
  
  
  defp do_connect(["serial", port], state) do
    do_connect(["serial", port, "9600"], state)
  end
  
  defp do_connect(["serial", _, _], state = %{uarts: []}) do
    {:reply, {:error, :no_free_uarts}, state}
  end
  
  defp do_connect(["serial", port, baud], state = %{uarts: [next_free_uart | _free_uarts]}) do
    attached_ports = UART.enumerate()
    case {Map.has_key?(attached_ports, port), parse_positive_integer(baud)} do
      {false, _} ->
        {:reply, {:error, :port_not_attached}, state}
      {_, :error} ->
        {:reply, {:error, :invalid_baud_rate}, state}
      {true, parsed_baud} ->
        case UART.open(next_free_uart, port, speed: parsed_baud, active: true) do
          :ok ->
            {
              :reply,
              :ok,
              state.conn_details |> Map.put_new(
                {:serial, port},
                {next_free_uart, <<>>})
            }
          error = {:error, _} ->
            {:reply, error, state}
        end
    end
  end
  
  defp do_connect([protocol, address, port], state) do
    case {parse_ip_address(address), parse_positive_integer(port)} do
      {{:error, :invalid_ip_address}, _}->
        {:reply, {:error, :invalid_ip_address}, state}
      {_, :error} ->
        {:reply, {:error, :invalid_port}, state}
      {ip, p} ->
        do_connect_network(protocol, ip, p, state)
    end
  end
  
  defp do_connect(_, state) do
    {:reply, {:error, :invalid_protocol}, state}
  end
  
  
  defp do_connect_network("udp", address, port, state) do
    {:ok, socket} = :gen_udp.open(port, [:binary, ip: address, active: :true])
    {:reply,
      :ok,
      put_in(state, [:conn_details, {:udp, address, port}], socket)
    }
  end
  
  defp do_connect_network("tcp", _address, _port, state) do
    {:reply, "tcp not implemented", state} # TODO
  end
  
  
  @doc """
  Use callbacks from generated MAVLink dialect module to ensure
  message checksum matches, restore trailing zero bytes if truncation
  occurred and unpack the message payload. See:
  
    https://mavlink.io/en/guide/serialization.html
    
  for purpose of this and following functions.
  """
  defp validate_and_route_message_frame(state = %{dialect: dialect},
        version, conn_key, raw, payload_length, sequence_number,
        source_system_id, source_component_id, message_id,
        payload, checksum) do
    case apply(dialect, :msg_crc_size, [message_id]) do
      {:ok, crc, expected_length} ->
        case checksum == (
               :binary.bin_to_list(
                  raw,
                  {1, payload_length + elem({0, 5, 9}, version)})
                |> x25_crc()
                |> x25_crc([crc])) do
          true ->
            payload_truncated_length = 8 * (expected_length - payload_length)
            case apply(dialect, :unpack, [
                   message_id,
                   payload <> <<0::size(payload_truncated_length)>>]) do
              {:ok, message} ->
                state
                |> route_message_remote(message, version, conn_key, raw)
                |> route_message_local(message, source_system_id, source_component_id,
                     version, conn_key)
                |> update_route_info(conn_key, source_system_id, source_component_id,
                     sequence_number, version, conn_key)
              _ ->
                # Couldn't unpack message
                state
            end
          _ ->
            # Checksum didn't match
            state
        end
      {:error, _} ->
        # TODO Message id not in dialect MAVLink says we should broadcast anyway but won't it bounce forever?
        state
    end
  end
  
  
  @doc """
  Systems should forward messages to another link if any of these conditions hold:
  
  - It is a broadcast message (target_system field omitted or zero).
  - The target_system does not match the system id and the system knows the link of
    the target system (i.e. it has previously seen a message from target_system on
    the link).
  - The target_system matches its system id and has a target_component field, and the
    system has seen a message from the target_system/target_component combination on
    the link.
  - Non-broadcast messages must only be sent (or forwarded) to known destinations
    (i.e. a system must previously have received a message from the target
    system/component).
  """
  defp route_message_remote(state, message, version, conn_key, raw) do
    state # TODO
  end
  
  
  @doc """
  Forward a message to a subscribing Elixir process.
  
  Systems/components should process a message locally if any of these conditions hold:

  - It is a broadcast message (target_system field omitted or zero).
  - The target_system matches its system id and target_component is broadcast
    (target_component omitted or zero).
  - The target_system matches its system id and has the component's target_component
  - The target_system matches its system id and the component is unknown
    (i.e. this component has not seen any messages on any link that have the message's
    target_system/target_component).
  """
  defp route_message_local(state, message, source_system_id, source_component_id,
       version, conn_key) do
    state # TODO
  end
  
  
  @doc """
  - Map system/component ids to connections on which they have been seen
  - Record skipped message sequence numbers to monitor connection health
  - Systems should also check for SYSTEM_TIME messages with a decrease in time_boot_ms,
    as this indicates that the system has rebooted. In this case it should clear stored
    routing information (and might perform other actions that are useful following a
    reboot - e.g. re-fetching parameters and home position etc.).
  """
  defp update_route_info(state, conn_key, source_system_id, source_component_id,
         sequence_number, version, conn_key) do
    state # TODO
  end
  
end
