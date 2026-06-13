defmodule MAVLink.RouteTable do
  @moduledoc false

  use GenServer
  require Logger

  @routes :mavlink_routes
  @peers :mavlink_peers
  @subscribers :mavlink_subscribers

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(peer_pid, type) when is_pid(peer_pid) do
    :ets.insert(@peers, {peer_pid, type})
    :ok
  end

  def register_wire(peer_pid, connection_key) when is_pid(peer_pid) do
    :ets.insert(@peers, {{peer_pid, connection_key}, :wire})
    :ok
  end

  def unregister(peer_pid) when is_pid(peer_pid) do
    :ets.match_delete(@peers, {peer_pid, :_})
    :ets.match_delete(@peers, {{peer_pid, :_}, :_})
    :ets.match_delete(@routes, {:_, {peer_pid, :_}})
    :ok
  end

  def put_route({sys, comp}, {peer_pid, dest_meta})
      when is_integer(sys) and is_integer(comp) and is_pid(peer_pid) do
    :ets.insert(@routes, {{sys, comp}, {peer_pid, dest_meta}})
    :ok
  end

  def matching_peers(target_sys, target_comp) do
    @routes
    |> :ets.tab2list()
    |> Enum.filter(fn {{sid, cid}, _} ->
      (target_sys == 0 or target_sys == sid) and
        (target_comp == 0 or target_comp == cid)
    end)
    |> Enum.map(fn {_, dest} -> dest end)
  end

  def all_wire_peers do
    @peers
    |> :ets.tab2list()
    |> Enum.filter(fn
      {{_pid, _key}, :wire} -> true
      _ -> false
    end)
    |> Enum.map(fn {{pid, key}, :wire} -> {pid, key} end)
  end

  def subscribe(query, pid) when is_map(query) and is_pid(pid) do
    GenServer.call(__MODULE__, {:subscribe, query, pid})
  end

  def unsubscribe(pid) when is_pid(pid) do
    GenServer.call(__MODULE__, {:unsubscribe, pid})
  end

  def matching_subscribers(%MAVLink.Frame{} = frame) do
    @subscribers
    |> :ets.tab2list()
    |> Enum.flat_map(fn {pid, query} ->
      case match_subscriber(query, frame) do
        nil -> []
        delivery -> [{pid, delivery}]
      end
    end)
  end

  @impl true
  def init(_) do
    :ets.new(@routes, [:named_table, :public, :set, read_concurrency: true])
    :ets.new(@peers, [:named_table, :public, :bag, read_concurrency: true])
    :ets.new(@subscribers, [:named_table, :public, :bag, read_concurrency: true])
    restore_subscriptions()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:subscribe, query, pid}, _, state) do
    Process.monitor(pid)
    :ets.insert(@subscribers, {pid, query})
    update_subscription_cache()
    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, pid}, _, state) do
    :ets.match_delete(@subscribers, {pid, :_})
    update_subscription_cache()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state) do
    :ets.match_delete(@subscribers, {pid, :_})
    update_subscription_cache()
    {:noreply, state}
  end

  defp restore_subscriptions do
    case Agent.start(fn -> [] end, name: MAVLink.SubscriptionCache) do
      {:ok, _} ->
        :ok

      {:error, {:already_started, _}} ->
        for entry <- Agent.get(MAVLink.SubscriptionCache, & &1) do
          {query, pid} = normalize_subscription_entry(entry)

          if Process.alive?(pid) do
            Process.monitor(pid)
            :ets.insert(@subscribers, {pid, query})
          end
        end
    end
  end

  defp normalize_subscription_entry({pid, query}) when is_pid(pid) and is_map(query), do: {query, pid}
  defp normalize_subscription_entry({query, pid}) when is_map(query) and is_pid(pid), do: {query, pid}

  defp update_subscription_cache do
    subs =
      @subscribers
      |> :ets.tab2list()
      |> Enum.map(fn {pid, query} -> {query, pid} end)

    Agent.update(MAVLink.SubscriptionCache, fn _ -> subs end)
    :ok
  end

  defp match_subscriber(
         %{
           message: q_message_type,
           source_system: q_source_system,
           source_component: q_source_component,
           target_system: q_target_system,
           target_component: q_target_component,
           as_frame: as_frame?
         },
         frame = %MAVLink.Frame{
           source_system: source_system,
           source_component: source_component,
           target_system: target_system,
           target_component: target_component,
           target: target,
           message: message
         }
       ) do
    message_type =
      case message do
        %{__struct__: struct} -> struct
        _ -> MAVLink.UnknownMessage
      end

    if (q_message_type == nil or q_message_type == message_type) and
         (q_source_system == 0 or q_source_system == source_system) and
         (q_source_component == 0 or q_source_component == source_component) and
         (q_target_system == 0 or
            (target != :broadcast and target != :component and q_target_system == target_system)) and
         (q_target_component == 0 or
            (target != :broadcast and target != :system and q_target_component == target_component)) do
      if as_frame?, do: frame, else: message
    else
      nil
    end
  end
end
