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
  
  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1]
  import Enum, only: [reduce: 3, filter: 2]
  
  alias MAVLink.Frame
  alias MAVLink.Message
  alias MAVLink.Router
  alias MAVLink.SerialConnection
  alias MAVLink.TCPOutConnection
  alias MAVLink.Types
  alias MAVLink.UDPInConnection
  alias MAVLink.UDPOutConnection
  
  
  # Router State
  # ------------
  # connections are configured by the user when the server starts. Broadcast messages
  # (e.g. heartbeat) are always sent to all connections, whereas targeted messages
  # are only sent to systems we have already seen and recorded in the routes map.
  # subscriptions are where we record the queries and pids of local Elixir processes
  # to forward messages to.

  defstruct [
    dialect: nil,                             # Generated dialect module
    system: 240,                               # Default to ground station
    component: 1,
    connection_strings: [],                   # Connection descriptions from user
    connections: %{},                         # %{socket|port: MAVLink.*_Connection}
    routes: %{},                              # Connection and MAVLink version tuple keyed by MAVLink addresses
    subscriptions: [],                        # Local Connection Elixir process queries
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
               connections: %{},
               routes: %{mavlink_address: {mavlink_connection, Types.version}},
               subscriptions: [],
               sequence_number: Types.sequence_number,
               uarts: [pid]
             }
  
             
             
             
  ##############
  # Router API #
  ##############
  
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
  
    message:          message_module
    source_system:    integer 0..255
    source_component: integer 0..255
    target_system:    integer 0..255
    target_component: integer 0..255
    as_frame:         true|false (default false)
    
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
            target_component: 0,
            as_frame: false
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
  def pack_and_send(message, version \\ 2) do
    # We can only pack payload at this point because we nee router state to get source
    # system/component and sequence number for frame
    try do
      {:ok, message_id, {:ok, crc_extra, _, targeted?}, payload} = Message.pack(message, version)
      {target_system, target_component} = if targeted? do
        {message.target_system, message.target_component}
      else
        {0, 0}
      end
      GenServer.cast(
        __MODULE__,
        {
          :send,
          struct(Frame, [
            version: version,
            message_id: message_id,
            target_system: target_system,
            target_component: target_component,
            targeted?: targeted?,
            message: message,
            payload: payload,
            crc_extra: crc_extra])
        }
      )
      :ok
    rescue
      # Need to catch Protocol.UndefinedError - happens with SimState (Common) and Simstate (APM)
      # messages because non-case-sensitive filesystems (including OSX thanks @noobz) can't tell
      # the difference between generated module beam files. Work around is comment out one of the
      # message definitions and regenerate.
      Protocol.UndefinedError ->
        {:error, :protocol_undefined}
    end
  end
  
  
  
  
  #######################
  # GenServer Callbacks #
  #######################
  
  @impl true
  def init(%{dialect: nil}) do
    {:error, :no_mavlink_dialect_set}
  end
  
  def init(state = %{connection_strings: connection_strings}) do
    {:ok, reduce(connection_strings, struct(Router, state), &connect/2)}
  end
  
  
  @impl true
  def handle_cast({:subscribe, query, pid}, state) do
    subscribe(query, pid, state)
  end
  
  def handle_cast({:unsubscribe, pid}, state) do
    unsubscribe(pid, state)
  end
  
  def handle_cast(
        {:send, frame},
        state=%Router{
          sequence_number: sequence_number,
          system: system,
          component: component}) do
    {
      :noreply,
      route({
        :ok,
        :local,
        Frame.pack_frame(
          struct(frame, [
            sequence_number: sequence_number,
            source_system: system,
            source_component: component
          ])
        ),
        struct(state, [
          sequence_number: rem(sequence_number + 1, 255)
        ])}
      )
    }
  end
  

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state), do: subscriber_down(pid, state)
  
  # Process incoming messages from connection ports
  def handle_info(message = {:udp, socket, address, port, _},
        state = %Router{connections: connections, dialect: dialect}) do
    {
       :noreply,
       case connections[{socket, address, port}] do
         connection = %UDPInConnection{} ->
           UDPInConnection.handle_info(message, connection, dialect)
         connection = %UDPOutConnection{} ->
           UDPOutConnection.handle_info(message, connection, dialect)
         nil ->
           # New unseen UDPIn client
           UDPInConnection.handle_info(message, nil, dialect)
       end
       |> update_route_info(state)
       |> route
    }
  end
  
  def handle_info(message = {:tcp, socket, _}, state) do
    {
      :noreply,
      TCPOutConnection.handle_info(message, state.connections[socket], state.dialect)
      |> update_route_info(state)
      |> route
    }
  end
  
#  def handle_info(message = {:serial, port, _, _, _}, state) do
#    {
#      :noreply,
#      SerialConnection.handle_info(message, state.connections[port], state.dialect)
#      |> update_route_info(state)
#      |> route
#    }
#  end
  
  def handle_info(_, state) do
    {:noreply, state}
  end
  
  
  
  
  ####################
  # Helper Functions #
  ####################
  
  
  defp connect(connection_string, state) when is_binary(connection_string) do
    connect(String.split(connection_string, [":", ","]), state)
  end
  
  defp connect(tokens = ["serial" | _], state), do: SerialConnection.connect(tokens, state)
  defp connect(tokens = ["udpin" | _], state), do: UDPInConnection.connect(validate_address_and_port(tokens), state)
  defp connect(tokens = ["udpout" | _], state), do: UDPOutConnection.connect(validate_address_and_port(tokens), state)
  defp connect(tokens = ["tcpout" | _], state), do: TCPOutConnection.connect(validate_address_and_port(tokens), state)
  defp connect([invalid_protocol | _], _), do: raise(ArgumentError, message: "invalid protocol #{invalid_protocol}")
  
  
  # Map system/component ids to connections on which they have been seen for targeted messages
  # Keep a list of all connections we have received messages from for broadcast messages
  defp update_route_info({:ok,
        source_connection_key,
        source_connection,
        frame=%Frame{
          source_system: source_system,
          source_component: source_component
        }
      },
      state=%Router{routes: routes, connections: connections}) do
    {
      :ok,
      source_connection_key,
      frame,
      struct(
        state,
        [
          routes: Map.put(
            routes,
            {source_system, source_component},
            source_connection_key),
          connections: Map.put(
            connections,
            source_connection_key,
            source_connection)
        ]
      )
    }
    
  end
  
  # Connections buffers etc still need to be updated if there is an error
  defp update_route_info(
         {:error, reason, connection_key, connection},
         state=%Router{connections: connections}) do
    {
      :error,
      reason,
      struct(
        state,
        [
          connections: Map.put(
            connections,
            connection_key,
            connection
          )
        ]
      )
    }
  end
  
  # Broadcast un-targeted messages to all connections except the
  # source we received the message from
  defp route({:ok,
        source_connection_key,
        frame=%Frame{target_system: 0, target_component: 0},
        state=%Router{connections: connections, subscriptions: subscriptions}}) do
    for {connection_key, connection} <- connections do
      unless match?(^connection_key, source_connection_key) do
        forward(connection, frame)
      end
    end
    forward(:local, frame, subscriptions)
    state
  end
  
  # Only send targeted messages to observed system/components
  defp route({:ok,
        _,
        frame=%Frame{target_system: target_system, target_component: target_component},
        state=%Router{connections: connections}}) do
    for connection_key <- matching_system_components(target_system, target_component, state) do
      forward(connections[connection_key], frame)
    end
    forward(:local, frame, state.subscriptions)
    state
  end
  
  defp route({:error, _reason, state=%Router{}}), do: state
  
  
  # Delegate sending a message to non-local connection-type specific code
  defp forward(connection=%UDPInConnection{}, frame), do: UDPInConnection.forward(connection, frame)
  defp forward(connection=%UDPOutConnection{}, frame), do: UDPOutConnection.forward(connection, frame)
  defp forward(connection=%TCPOutConnection{}, frame), do: TCPOutConnection.forward(connection, frame)
 
  #  Forward a message to a local subscribed Elixir process.
  #  TODO after all the changes perhaps we could try factoring out LocalConnection again...
  defp forward(:local, frame = %Frame{
        source_system: source_system,
        source_component: source_component,
        target_system: target_system,
        target_component: target_component,
        targeted?: targeted?,
        message: message = %{__struct__: message_type}
      }, subscriptions) do
    for {
          %{
            message: q_message_type,
            source_system: q_source_system,
            source_component: q_source_component,
            target_system: q_target_system,
            target_component: q_target_component,
            as_frame: as_frame?
          },
          pid} <- subscriptions do
      if (q_message_type == nil or q_message_type == message_type)
          and (q_source_system == 0 or q_source_system == source_system)
          and (q_source_component == 0 or q_source_component == source_component)
          and (q_target_system == 0 or (targeted? and q_target_system == target_system))
          and (q_target_component == 0 or (targeted? and q_target_component == target_component)) do
        send(pid, (if as_frame?, do: frame, else: message))
      end
    end
  end

  
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
  
  
  # Subscription request from subscriber
  defp subscribe(query, pid, state) do
    # Monitor so that we can unsubscribe dead processes
    Process.monitor(pid)
    # Uniq prevents duplicate subscriptions
    {
      :noreply,
      %Router{state | subscriptions: Enum.uniq([{query, pid} | state.subscriptions])}
    }
  end
  
  
  # Unsubscribe request from subscriber
  defp unsubscribe(pid, state) do
    {:noreply, %Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  
  # Automatically unsubscribe a dead subscriber process
  defp subscriber_down(pid, state) do
    {:noreply, %Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
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
    ) |> Enum.map(fn  {_, ck} -> ck end)
  end
  
end
