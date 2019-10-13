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
  alias MAVLink.TCPConnection
  alias MAVLink.Types
  alias MAVLink.UDPConnection
  
  
  # Router State
  # ------------
  # connections are configured by the user when the server starts. Broadcast messages
  # (e.g. heartbeat) are always sent to all connections, whereas targeted messages
  # are only sent to systems we have already seen and recorded in the routes map.
  # subscriptions are where we record the queries and pids of local Elixir processes
  # to forward messages to.

  defstruct [
    dialect: nil,                             # Generated dialect module
    system: 25,                               # Default to ground station
    component: 250,
    connection_strings: [],                   # Connection descriptions from user
    connections: MapSet.new(),                # %{MAVLink.UDP|TCP|Serial_Connection}
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
               connections: %MapSet{},
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
  def pack_and_send(message, version \\ 2) do
    # We can only pack payload at this point because we need
    # router state to get source system/component and sequence number
    {:ok, message_id, {:ok, crc_extra, _, targeted?}, payload} = Message.pack(message)
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
  
  def handle_cast({:send, frame}, state) do
    updated_frame = Frame.pack_frame(
      struct(frame, [
        sequence_number: state.sequence_number,
        source_system: state.system,
        source_component: state.component
      ])
    )
    updated_state = struct(state, [sequence_number: rem(state.sequence_number + 1, 255)])
    {:noreply, route({:ok, :local, updated_frame, updated_state})}
  end
  

  #Unsubscribe dead subscribers first, then process incoming messages from connection ports
  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state), do: subscriber_down(pid, state)
  def handle_info(message = {:udp, _, _, _, _}, state), do: {:noreply, UDPConnection.handle_info(message, state) |> route()}
  def handle_info(message = {:tcp, _, _, _, _}, state), do: {:noreply, TCPConnection.handle_info(message, state) |> route()}
  def handle_info(message = {:serial, _, _, _, _}, state), do: {:noreply, SerialConnection.handle_info(message, state) |> route()}
  def handle_info(_, state), do: {:noreply, state}
  
  
  # Broadcast un-targeted messages to all connections except the
  # source we received the message from
  def route({:ok,
        source_connection,
        frame=%Frame{target_system: 0, target_component: 0},
        state=%Router{connections: connections}}) do
    for connection <- connections do
      # TODO This is why udpin vs udpout exists - shouldn't forward to our own ip and socket if udpin
      # TODO Get double messages...
      unless match?(^connection, source_connection) do
        forward(connection, frame, state)
      end
    end
    forward(:local, frame, state)
    update_route_info(source_connection, frame, state)
  end
  
  # Only send targeted messages to observed system/components
  def route({:ok,
        source_connection,
        frame=%Frame{target_system: target_system, target_component: target_component},
        state=%Router{}}) do
    for connection <- matching_system_components(target_system, target_component, state) do
      forward(connection, frame, state)
    end
    forward(:local, frame, state)
    update_route_info(source_connection, frame, state)
  end
  
  def route({:error, state}), do: state
  
  
  ####################
  # Helper Functions #
  ####################
  
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
  
  
  # Map system/component ids to connections on which they have been seen
  defp update_route_info(:local, _, state), do: state
  
  defp update_route_info(receiving_connection,
         %Frame{
           source_system: source_system,
           source_component: source_component},
         state=%Router{routes: routes}) do
    struct(
      state,
      [
        routes: Map.put(
          routes,
          {source_system, source_component},
          receiving_connection)
      ]
    )
  end
  
  
  defp subscribe(query, pid, state) do
    # Monitor so that we can unsubscribe dead processes
    Process.monitor(pid)
    # Uniq prevents duplicate subscriptions
    {:noreply, %Router{state | subscriptions: Enum.uniq([{query, pid} | state.subscriptions])}}
  end
  
  
  defp unsubscribe(pid, state) do
    {:noreply, %Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  
  defp subscriber_down(pid, state) do
    {:noreply, %Router{state | subscriptions: filter(state.subscriptions, & not match?({_, ^pid}, &1))}}
  end
  
  
  # Delegate sending a message to non-local connection-type specific code
  defp forward(connection=%UDPConnection{}, frame, state), do: UDPConnection.forward(connection, frame, state)
 
  #  Forward a message to a local subscribing Elixir process.
  defp forward(:local, %Frame{
        source_system: source_system,
        source_component: source_component,
        target_system: target_system,
        target_component: target_component,
        targeted?: targeted?,
        message: message = %{__struct__: message_type}
      }, state) do
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
          and (q_target_system == 0 or (targeted? and q_target_system == target_system))
          and (q_target_component == 0 or (targeted? and q_target_component == target_component)) do
        send(pid, message)
      end
    end
  end
  
end
