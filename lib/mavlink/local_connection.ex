defmodule MAVLink.LocalConnection do
  @moduledoc false

  use GenServer
  require Logger

  alias MAVLink.{Frame, Forwarder, LocalConnection, RouteTable}

  defstruct [
    system: nil,
    component: nil,
    sequence_number: 0,
    dialect: nil
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def pack_and_send(message, version \\ 2) do
    GenServer.cast(__MODULE__, {:send, message, version})
  end

  @impl true
  def init(%{system: system, component: component, dialect: dialect}) do
    RouteTable.register(self(), :local)
    {:ok, %LocalConnection{system: system, component: component, dialect: dialect, sequence_number: 0}}
  end

  @impl true
  def handle_cast({:send, message, version}, state) do
    case pack_message(message, version, state) do
      {:ok, frame, new_state} ->
        :ok = Forwarder.route(self(), :local, frame)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.debug("pack_and_send failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:local, frame}, state) do
    case pack_frame(frame, state) do
      {:ok, packed, new_state} ->
        :ok = Forwarder.route(self(), :local, packed)
        {:noreply, new_state}

      error ->
        Logger.debug("local frame pack failed: #{inspect(error)}")
        {:noreply, state}
    end
  end

  # Legacy delegate API for tests
  def handle_info({:local, frame}, receiving_connection, _dialect) do
    legacy_pack(frame, receiving_connection)
  end

  def forward(_connection, _frame), do: :ok

  def subscribe(query, pid, local_connection) do
    merged =
      %{
        message: nil,
        source_system: 0,
        source_component: 0,
        target_system: 0,
        target_component: 0,
        as_frame: false,
        as_raw: false
      }
      |> Map.merge(query)

    RouteTable.subscribe(merged, pid)
    local_connection
  end

  def unsubscribe(pid, local_connection) do
    RouteTable.unsubscribe(pid)
    local_connection
  end

  def subscriber_down(_pid, local_connection), do: local_connection

  def connect(_key, _system, _component), do: :ok

  defp pack_message(message, version, %LocalConnection{} = state) do
    try do
      {:ok, message_id, {:ok, crc_extra, _, target}, payload} = MAVLink.Message.pack(message, version)

      {target_system, target_component} =
        if target != :broadcast do
          {message.target_system, Map.get(message, :target_component, 0)}
        else
          {0, 0}
        end

      frame =
        struct(Frame, [
          version: version,
          message_id: message_id,
          target_system: target_system,
          target_component: target_component,
          target: target,
          message: message,
          payload: payload,
          crc_extra: crc_extra
        ])

      pack_frame(frame, state)
    rescue
      Protocol.UndefinedError -> {:error, :protocol_undefined}
    end
  end

  defp pack_frame(frame, %LocalConnection{system: system, component: component, sequence_number: seq, dialect: dialect}) do
    packed =
      frame
      |> struct(source_system: system, source_component: component, sequence_number: seq)
      |> Frame.pack_frame()

    {:ok, packed, %LocalConnection{system: system, component: component, sequence_number: rem(seq + 1, 255), dialect: dialect}}
  end

  defp legacy_pack(frame, %LocalConnection{system: system, component: component, sequence_number: seq} = lc) do
    {
      :ok,
      :local,
      struct(lc, sequence_number: rem(seq + 1, 255)),
      frame
      |> struct(source_system: system, source_component: component, sequence_number: seq)
      |> Frame.pack_frame()
    }
  end
end
