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
  require Logger
  
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1, x25_crc: 1, x25_crc: 2]
  import Enum, only: [reduce: 3, filter: 2]
  
  alias MAVLink.Frame
  alias MAVLink.Pack, as: Message
  alias MAVLink.Router
  alias MAVLink.SerialConnection
  alias MAVLink.TCPConnection
  alias MAVLink.Types
  alias MAVLink.UDPConnection
  
  
  # Router state

  defstruct [
    dialect: nil,                             # Generated dialect module
    system: 25,                            # Default to ground station
    component: 250,
    connection_strings: [],                   # Connection descriptions from user
    connections: %{},                         # %{MAVLink.UDP|TCP|Serial_Connection: mavlink_version}
    routes: %{},                              # Connection and MAVLink version tuple keyed by MAVLink addresses
    subscriptions: [],                        # Elixir process queries
    sequence_number: 0,                       # Sequence number of next sent message
    uarts: []                                 # Circuit.UART Pool
  ]
  @type mavlink_address :: Types.mavlink_address  # Can't used qualified type as map key
  @type mavlink_connection :: Types.connection
  @type t :: %Router{
               dialect: module | nil,
               system: non_neg_integer,
               component: non_neg_integer,
               connection_strings: [ String.t ],
               connections: %{mavlink_connection: Types.version},
               routes: %{mavlink_address: {mavlink_connection, Types.version}},
               subscriptions: [],
               sequence_number: Types.sequence_number,
               uarts: [pid]
             }
  
             
  #######
  # API #
  #######
  
  @spec start_link(%{dialect: module, system: non_neg_integer, component: non_neg_integer,
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
    source_system:    integer 0..255
    source_component: integer 0..255
    target_system:    integer 0..255
    target_component: integer 0..255
    
  For example:
  
  ```
    MAVLink.Router.subscribe message: MAVLink.Message.Heartbeat, source_system: 1
  ```
  """
  @type subscribe_query_id_key :: :source_system | :source_component | :target_system | :target_component
  @spec subscribe([{:message, Message.t} | {subscribe_query_id_key, 0..255}]) :: :ok
  def subscribe(query \\ []) do
    with message <- Keyword.get(query, :message),
        true <- message == nil or Code.ensure_loaded?(message) do
      GenServer.cast(
        __MODULE__,
        {
          :subscribe,
          [
            message: nil,
            source_system: 0,
            source_component: 0,
            target_system: 0,
            target_component: 0
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
  Un-subscribes calling process from all existing subscriptions
  """
  @spec unsubscribe() :: :ok
  def unsubscribe(), do: GenServer.cast(__MODULE__, {:unsubscribe, self()})
  
  
  
  @doc """
  Send a MAVLink message to one or more recipients using available
  connections. For now if destination is unreachable it will fail
  silently.
  """
  def send(message) do
    # We can only pack payload at this point because we need
    # router state to get source system/component and sequence number
    {:ok, message_id, {:ok, crc_extra, _, targeted?}, payload} = pack(message)
    {target_system, target_component} = if targeted? do
      {message.target_system, message.target_component}
    else
      {0, 0}
    end
    GenServer.cast(
      __MODULE__,
      {
        :send,
        Frame |> struct([
          message_id: message_id,
          target_system: target_system,
          target_component: target_component,
          payload: payload,
          crc_extra: crc_extra])
      }
    )
  end
  
  
  #############
  # Callbacks #
  #############
  
  @impl true
  def init(%{dialect: nil}) do
    {:error, :no_mavlink_dialect_set}
  end
  
  def init(state = %{connection_strings: connection_strings}) do
    {:ok, reduce(connection_strings, struct(Router, state), &connect/2)}
  end
  
  
  @impl true
  def handle_cast({:subscribe, query, pid}, state) do
    # Monitor so that we can unsubscribe dead processes
    Process.monitor(pid)
    # Uniq prevents duplicate subscriptions
    {:noreply, %Router{state | subscriptions:
      Enum.uniq([{query, pid} | state.subscriptions])}}
  end
  
  def handle_cast({:unsubscribe, pid}, state) do
    {:noreply, %Router{state | subscriptions:
      filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  def handle_cast({:send, frame}, state) do
    updated_frame = pack_frame(frame |> struct([
      sequence_number: state.sequence_number,
      source_system: state.source_system,
      source_component: state.source_component
    ]))
    updated_state = state |> struct([sequence_number: rem(sequence_number + 1, 255)])
    {:noreply, route(:local, updated_frame, updated_state)}
  end
  
  
  @doc """
  Unsubscribe dead subscribers first, then process incoming messages from connection ports
  """
  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state) do
    {:noreply, %Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  def handle_info(message = {:udp, _, _, _, _}, state), do: {:noreply, UDPConnection.handle_info(message, state)}
  def handle_info(message = {:tcp, _, _, _, _}, state), do: {:noreply, TCPConnection.handle_info(message, state)}
  def handle_info(message = {:serial, _, _, _, _}, state), do: {:noreply, SerialConnection.handle_info(message, state)}
  def handle_info(_, state), do: {:noreply, state}
  
  
  def route(
        :local,
        frame=%Frame{target_system: target_system, target_component: target_component},
        state=%Router{connections: connections}) do
    # Broadcast from local to all connections using connection MAVLink version
    for {forward_connection, forward_version} <- Map.to_list(connections) do
      forward(
        forward_connection,
        frame |> struct([version:
          case forward_version do
            1 ->
              1
            10 ->
              1
            2 ->
              2
            20 ->
              2
          end
        ]),
        state
      )
    end
  end
  
  def route(
        :local,
        frame=%Frame{target_system: target_system, target_component: target_component},
        state=%Router{routes: routes, connections: connections}) do
    # Targeted message from local using route MAVLink version
    # unless overridden by connection with forced MAVLink version
    case Map.get(routes, {target_system, target_component}, :not_seen) do
      {route_connection, route_version} ->
        forward_version = max(route_version,          # update_route_info() only updates
          Map.get(connections, route_connection, -1)) # version in connections
        forward(
          forward_connection,
          frame |> struct([version:
            case forward_version do
              1 ->
                1
              10 ->
                1
              2 ->
                2
              20 ->
                2
            end
          ]),
          state)
        :not_seen ->
          state             # Only send if we've received a message from target
    end
  end
  
  
  def route(
        receiving_connection,
        frame,
        state
      ) do
    # Broadcast or targeted message, forward to all connections
    # and let them decide whether or not to send. This delegation allows the
    # local connection to snoop and in future might be used to support
    # specialised connection types for redundancy or high priority messages.
    for {forward_connection, forward_version} <- Map.to_list(connections) do
      forward(
        forward_connection,
        case {received_mavlink_version, forward_version} do
          {1, 1} ->
            raw           # Match
          {1, 2} ->
            raw           # Not forced to MAVLink version 2
          {1, 10} ->
            raw           # Match forced version
          {2, 1} ->
            raw           # Not forced to MAVLink version 1
          {2, 2} ->
            raw           # Match
          {2, 20} ->
            raw           # Match forced version
          _ ->
            nil           # Doesn't match forced version, don't forward
        end,state)
    end
  end
  
  
  ###########
  # Helpers #
  ###########
  
  defp connect(connection_string, state) when is_binary(connection_string) do
    connect(String.split(connection_string, [":", ","]), state)
  end
  
  defp connect(tokens = ["serial" | _], state), do: SerialConnection.connect(tokens, state)
  defp connect(tokens = ["udp" | _], state), do: UDPConnection.connect(validate_address_and_port(tokens), state)
  defp connect(tokens = ["tcp" | _], state), do: TCPConnection.connect(validate_address_and_port(tokens), state)
  defp connect([invalid_protocol | _], _), do: raise(ArgumentError, message: "invalid protocol #{invalid_protocol}")

  
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
  
  
  # Known system/components matching target with 0 wildcard
  defp matching_system_components(q_system, q_component,
         %Router{routes: routes}) do
    Enum.filter(
      routes,
      fn {{sid, cid}, _} ->
          (q_system == 0 or q_system == sid) and
          (q_component == 0 or q_component == cid)
      end
    )
  end
  
  
  
  # Delegate sending a message to connection-type specific code
  defp forward(connection=%UDPConnection{}, frame, state) do
    UDPConnection.forward(connection, frame, state)
  end

  # TODO others
  

  

  #  Forward a message to a subscribing Elixir process.
  #
  #  We just let subscribers choose what messages they want to receive, which should
  #  not be a problem for other systems as long as the various MAVLink protocols are
  # implemented by the set of subscribers.
  defp route_message_local(
         state,
         source_system, source_component, targeted?,
         message = %{__struct__: message_type}) do
    for {
          %{
            message: q_message_type,
            source_system: q_source_system,
            source_component: q_source_component,
            target_system: q_target_system,
            target_component: q_target_component},
          pid} <- state.subscriptions do
      if (q_message_type == nil or q_message_type == message_type)
          and (q_source_system == 0 or q_source_system == source_system)
          and (q_source_component == 0 or q_source_component == source_component)
          and (q_target_system == 0 or (targeted? and q_target_system == message.target_system))
          and (q_target_component == 0 or (targeted? and q_target_component == message.target_system)) do
        send(pid, message)
      end
    end
    state
  end
  
  
  # Map system/component ids to connections on which they have been seen, and
  # remember maximum MAVLink version at connection/system-component level so that
  # we can mirror that version when sending.
  defp update_route_info(receiving_connection,
         frame=%Frame{source_system: source_system,
           source_component: source_component, version: version},
         state=%Router{routes: routes}) do
    state |> struct([
      routes: Map.update(
        routes,
        {source_system, source_component},
        {receiving_connection, version},
        fn {receiving_connection, old_version} ->
          {receiving_connection, max(old_version, version)} # Upgrade sys/comp to MAVLink 2 if we see it
        end),
      connections: Map.update(
        connections,
        receiving_connection,
        1,
        fn old_version ->
          max(old_version, version) # Upgrade connection to MAVLink 2 if we see it
        end
      )
    ])
    
  end
  
end
