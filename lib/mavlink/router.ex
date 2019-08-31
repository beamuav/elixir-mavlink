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
  
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1, x25_crc: 1, x25_crc: 2]
  import Enum, only: [reduce: 3, filter: 2]
  
  
  # Router state

  defstruct [
    dialect: nil,                             # Generated dialect module
    system_id: 25,                            # Default to ground station
    component_id: 250,
    connection_strings: [],                   # Connection descriptions from user
    connections: %{},                         # MAVLink.UDP|TCP|Serial_Connection
    system_component_connection_version: %{}, # Connection and MAVLink version keyed by {system_id, component_id} addresses
    subscriptions: [],                        # Elixir process queries
    uarts: []                                 # Circuit.UART Pool
  ]
  @type mavlink_address :: MAVLink.Types.mavlink_address  # Can't used qualified type as map key
  @type t :: %MAVLink.Router{
               dialect: module | nil,
               system_id: non_neg_integer,
               component_id: non_neg_integer,
               connection_strings: [ String.t ],
               connections: %{tuple: MAVLink.Types.connection},
               system_component_connection_version: %{mavlink_address: {tuple, non_neg_integer}},
               subscriptions: [],
               uarts: [pid]
             }
  
  
  # Client API
  @spec start_link(%{dialect: module, system_id: non_neg_integer, component_id: non_neg_integer,
    connection_strings: [String.t]}, [{atom, any}]) :: {:ok, pid}
  def start_link(state, opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      state,
      [{:name, __MODULE__} | opts])
  end
  
  
  @doc """
  Subscribes the calling process to messages matching the query.
  Zero or more of the following query keywords are supported:
  
    message:             message_module
    source_system_id:    integer 0..255
    source_component_id: integer 0..255
    target_system_id:    integer 0..255
    target_component_id: integer 0..255
    
  For example:
  
  ```
    MAVLink.Router.subscribe message: MAVLink.Message.Heartbeat, source_system_id: 1
  ```
  """
  @type subscribe_query_id_key :: :source_system_id | :source_component_id | :target_system_id | :target_component_id
  @spec subscribe([{:message, module} | {subscribe_query_id_key, 0..255}]) :: :ok
  def subscribe(query \\ []) do
    with message <- Keyword.get(query, :message),
        true <- message == nil or Code.ensure_loaded?(message) do
      GenServer.cast(
        __MODULE__,
        {
          :subscribe,
          [
            message: nil,
            source_system_id: 0,
            source_component_id: 0,
            target_system_id: 0,
            target_component_id: 0
          ]
          |> Keyword.merge(query)
          |> Enum.into(%{}),
          self()
        }
      )
    else
      false ->
        {:error, :invalid_message}
    end
  end
  
  
  @doc """
  Unsubscribes calling process from all existing subscriptions
  """
  @spec unsubscribe() :: :ok
  def unsubscribe() do
    GenServer.cast(
      __MODULE__,
      {
        :unsubscribe,
        self()
      }
    )
  end
  
  
  # Callbacks
  
  @impl true
  def init(%{dialect: nil}) do
    {:error, :no_mavlink_dialect_set}
  end
  
  def init(state = %{connection_strings: []}) do
    {:ok, struct(MAVLink.Router, state)}
  end
  
  def init(state = %{connection_strings: connection_strings = [_ | _]}) do
    {:ok, reduce(connection_strings, struct(MAVLink.Router, state), &connect/2)}
  end
  
  
  @impl true
  def handle_cast({:subscribe, query, pid}, state) do
    # Monitor so that we can unsubscribe dead processes
    Process.monitor(pid)
    
    # Uniq prevents duplicate subscriptions
    {:noreply, %MAVLink.Router{state | subscriptions: Enum.uniq([{query, pid} | state.subscriptions])}}
  end
  
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %MAVLink.Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  
  @doc """
  Unsubscribe dead subscribers first, then incoming messages from connections
  """
  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state) do
    {
      :noreply,
      %MAVLink.Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}
    }
  end
  
  def handle_info(message = {:udp, _, _, _, _}, state), do: MAVLink.UDPConnection.handle_info(message, state)
  def handle_info(message = {:tcp, _, _, _, _}, state), do: MAVLink.TCPConnection.handle_info(message, state)
  def handle_info(message = {:serial, _, _, _, _}, state), do: MAVLink.SerialConnection.handle_info(message, state)
  def handle_info(_, state), do: {:noreply, state}
  
  
  #  Use callbacks from generated MAVLink dialect module to ensure
  #  message checksum matches, restore trailing zero bytes if truncation
  #  occurred and unpack the message payload. See:
  #
  #    https://mavlink.io/en/guide/serialization.html
  #
  #  for purpose of this and following functions.
  def validate_and_route_message_frame(
        state = %MAVLink.Router{dialect: dialect},
        receiving_connection, _message_protocol_info,
        mavlink_version, _sequence_number, source_system_id, source_component_id,
        message_id, payload_length, payload, checksum, raw) do
    case apply(dialect, :msg_attributes, [message_id]) do
      {:ok, crc, expected_length, targeted?} ->
        case checksum == (
               :binary.bin_to_list(
                  raw,
                  {1, payload_length + elem({0, 5, 9}, mavlink_version)})
                |> x25_crc()
                |> x25_crc([crc])) do
          true ->
            payload_truncated_length = 8 * (expected_length - payload_length)
            case apply(dialect, :unpack, [
                   message_id,
                   payload <> <<0::size(payload_truncated_length)>>]) do
              {:ok, message} ->
                state
                |> route_message_remote(
                     receiving_connection,
                     mavlink_version,
                     message, raw)
                |> route_message_local(
                     source_system_id, source_component_id, targeted?,
                     message)
                |> update_route_info(
                     receiving_connection, mavlink_version,
                     source_system_id, source_component_id)
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
  
  
  # Helpers
  
  defp connect(connection_string, state) when is_binary(connection_string) do
    connect(String.split(connection_string, [":", ","]), state)
  end
  
  defp connect(tokens = ["serial" | _], state), do: MAVLink.SerialConnection.connect(tokens, state)
  defp connect(tokens = ["udp" | _], state), do: MAVLink.UDPConnection.connect(validate_address_and_port(tokens), state)
  defp connect(tokens = ["tcp" | _], state), do: MAVLink.TCPConnection.connect(validate_address_and_port(tokens), state)
  defp connect([invalid_protocol | _], _), do: raise ArgumentError, message: "invalid protocol #{invalid_protocol}"

  
  defp validate_address_and_port([protocol, address, port]) do
    case {parse_ip_address(address), parse_positive_integer(port)} do
      {{:error, :invalid_ip_address}, _}->
        raise ArgumentError, message: "invalid ip address #{address}"
      {_, :error} ->
        raise ArgumentError, message: "invalid port #{port}"
      {parsed_address, parsed_port} ->
        [protocol, parsed_address, parsed_port]
    end
  end
  
  
  #  Systems should forward messages to another link if any of these conditions hold:
  #
  #  - It is a broadcast message (target_system field omitted or zero).
  #  - The target_system does not match the system id and the system knows the link of
  #    the target system (i.e. it has previously seen a message from target_system on
  #    the link).
  #  - The target_system matches its system id and has a target_component field, and the
  #    system has seen a message from the target_system/target_component combination on
  #    the link.
  #  - Non-broadcast messages must only be sent (or forwarded) to known destinations
  #    (i.e. a system must previously have received a message from the target
  #    system/component).
  defp route_message_remote(
         state,
         _receiving_connection_key,
         _mavlink_version,
         _message, _raw) do
    state # TODO
  end
  

  #  Forward a message to a subscribing Elixir process. The MAVLink directions are:
  #
  #  Systems/components should process a message locally if any of these conditions hold:
  #
  #  - It is a broadcast message (target_system field omitted or zero).
  #  - The target_system matches its system id and target_component is broadcast
  #    (target_component omitted or zero).
  #  - The target_system matches its system id and has the component's target_component
  #  - The target_system matches its system id and the component is unknown
  #    (i.e. this component has not seen any messages on any link that have the message's
  #    target_system/target_component).
  #
  #  In our implementation we just let subscribers choose what messages they want
  #  to receive, which should not be a problem for other systems as long as the various
  #  MAVLink protocols are implemented by the set of subscribers.
  defp route_message_local(
         state,
         source_system_id, source_component_id, targeted?,
         message = %{__struct__: message_type}) do
    for {
          %{
            message: q_message_type,
            source_system_id: q_source_system_id,
            source_component_id: q_source_component_id,
            target_system_id: q_target_system_id,
            target_component_id: q_target_component_id},
          pid} <- state.subscriptions do
      if (q_message_type == nil or q_message_type == message_type)
          and (q_source_system_id == 0 or q_source_system_id == source_system_id)
          and (q_source_component_id == 0 or q_source_component_id == source_component_id)
          and (q_target_system_id == 0 or (targeted? and q_target_system_id == message.target_system))
          and (q_target_component_id == 0 or (targeted? and q_target_component_id == message.target_system)) do
        send(pid, message)
      end
    end
    state
  end
  
  
  #  Map system/component ids to connections on which they have been seen, and
  #  remember version of the most recent message so that we can mirror that
  #  version when sending.
  #
  #  This doesn't seem to be the right place to implement the other MAVLink
  #  routing directions:
  #
  #  - Recording dropped messages is only useful if you're sending SYS_STATUS
  #    messages, which seem to be more for autopilots than routing logic
  #  - Responses to SYSTEM_TIME resets are implemented by microservices
  #
  defp update_route_info(
         state, connection, mavlink_version,
         source_system_id, source_component_id) do
    %MAVLink.Router{
      state | system_component_connection_version:
      put_in(
        state.system_component_connection_version,
        [{source_system_id, source_component_id}],
        {connection, mavlink_version}
      )
    }
  end
  
end
