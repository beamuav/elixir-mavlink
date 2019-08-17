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
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1]
  
  
  # Client API
  
  
  def start_link(state, opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      state,
      [{:name, __MODULE__} | opts])
  end
  
  
  @ doc """
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
          String.split(connection_string, [":", ","]) |> do_connect(acc_state)
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
    <<0xfe,
      payload_length::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      system_id::unsigned-integer-size(8),
      component_id::unsigned-integer-size(8),
      message_id::unsigned-integer-size(8),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do

    {:noreply, validate_and_process_message(
        1,
        {:udp, addr, port},
        raw,
        payload_length,
        sequence_number,
        system_id,
        component_id,
        message_id,
        payload,
        checksum,
        state)}
  end
  
  def handle_info({:udp, _sock, addr, port, raw=
    <<0xfd,
      payload_length::unsigned-integer-size(8),
      0::unsigned-integer-size(8),   # TODO Rejecting all incompatible flags for now
      _compatible_flags::unsigned-integer-size(8),
      sequence_number::unsigned-integer-size(8),
      system_id::unsigned-integer-size(8),
      component_id::unsigned-integer-size(8),
      message_id::little-unsigned-integer-size(24),
      payload::binary-size(payload_length),
      checksum::little-unsigned-integer-size(16)>>}, state) do

    {:noreply, validate_and_process_message(
        2,
        {:udp, addr, port},
        raw,
        payload_length,
        sequence_number,
        system_id,
        component_id,
        message_id,
        payload,
        checksum,
        state)}
  end
  
  def handle_info({:udp, _sock, _addr, _port, _}, state) do
    IO.puts("Bad Packet")
    # TODO update statistics, or only with sequence numbers?
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
      state |> put_in([:conn_details, {:udp, address, port}], socket)
    }
  end
  
  defp do_connect_network("tcp", _address, _port, state) do
    {:reply, "tcp not implemented", state} # TODO
  end
  
  
  defp validate_and_process_message(
        version,
        conn_key,
        raw,
        payload_length,
        sequence_number,
        system_id,
        component_id,
        message_id,
        payload,
        checksum,
        state) do
    IO.puts "#{sequence_number}: Mavlink #{version} message #{message_id}"
    # TODO Up to here
    state
  end
  
end
