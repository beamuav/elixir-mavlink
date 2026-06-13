defmodule MAVLink.Router do
  @moduledoc """
  Thin API facade and connection coordinator for MAVLink routing.

  Wire I/O is handled by per-connection GenServers supervised by
  `MAVLink.ConnectionSupervisor`. Subscribe/unsubscribe and route
  tables are handled by `MAVLink.RouteTable`; forwarding by
  `MAVLink.Forwarder`.
  """

  use GenServer
  require Logger

  import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1]
  import Enum, only: [map: 2]

  alias MAVLink.Types
  alias MAVLink.Message
  alias MAVLink.Router
  alias MAVLink.LocalConnection
  alias MAVLink.RouteTable
  alias MAVLink.ConnectionSupervisor
  alias MAVLink.{SerialConnection, TCPOutConnection, UDPInConnection, UDPOutConnection}

  defstruct [
    dialect: nil,
    connection_strings: [],
    registry: %{}
  ]

  @type t :: %Router{
               dialect: module() | nil,
               connection_strings: [String.t()],
               registry: %{term() => pid()}
             }

  ##############
  # Router API #
  ##############

  @spec start_link(
          %{system: 1..255, component: 1..255, dialect: module, connection_strings: [String.t()]},
          [{atom, any}]
        ) :: {:ok, pid()}
  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, [{:name, __MODULE__} | opts])
  end

  @type subscribe_query_id_key :: :source_system | :source_component | :target_system | :target_component
  @spec subscribe([{:message, Message.t} | {subscribe_query_id_key, 0..255} | {:as_frame, boolean} | {:as_raw, boolean}]) ::
          :ok | {:error, :invalid_message}
  def subscribe(query \\ []) do
    with message <- Keyword.get(query, :message),
         true <- message == nil or Code.ensure_loaded?(message) do
      query =
        [
          message: nil,
          source_system: 0,
          source_component: 0,
          target_system: 0,
          target_component: 0,
          as_frame: false,
          as_raw: false
        ]
        |> Keyword.merge(query)
        |> Enum.into(%{})

      RouteTable.subscribe(query, self())
    else
      false -> {:error, :invalid_message}
    end
  end

  @spec unsubscribe() :: :ok
  def unsubscribe(), do: RouteTable.unsubscribe(self())

  def pack_and_send(message, version \\ 2) do
    LocalConnection.pack_and_send(message, version)
  end

  def connection_pid(key) do
    GenServer.call(__MODULE__, {:connection_pid, key})
  end

  #######################
  # GenServer Callbacks #
  #######################

  @impl true
  def init(%{dialect: nil}) do
    {:error, :no_mavlink_dialect_set}
  end

  def init(args) do
    _ = map(args.connection_strings, &ConnectionSupervisor.start_connection(&1, args.dialect))
    {:ok, %Router{dialect: args.dialect, connection_strings: args.connection_strings}}
  end

  @impl true
  def handle_call({:connection_pid, key}, _, state) do
    {:reply, Map.get(state.registry, key), state}
  end

  def handle_info({:register_connection, key, pid}, state) when is_pid(pid) do
    RouteTable.register_wire(pid, key)
    {:noreply, %{state | registry: Map.put(state.registry, key, pid)}}
  end

  def handle_info({:unregister_connection, key}, state) do
    {:noreply, %{state | registry: Map.delete(state.registry, key)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
