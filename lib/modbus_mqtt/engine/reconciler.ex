defmodule ModbusMqtt.Engine.Reconciler do
  @moduledoc """
  Continuously reconciles active connections from the database with the
  running per-connection engine supervisor trees.

  Responsibilities:
  - Start missing connection trees for active connections.
  - Stop running trees that are no longer active.
  - Restart running trees when connection/register definitions change.
  """
  use GenServer
  require Logger

  @default_reconcile_interval_ms 15_000
  # Debounce window for coalescing bursts of reconcile_now calls
  @debounce_ms 50

  @doc """
  Requests a reconciliation pass at the earliest opportunity.

  Multiple calls within a debounce window (default #{@debounce_ms}ms) are
  coalesced into a single pass, so bursts of DB writes only trigger one
  reconcile rather than one per write.
  """
  def reconcile_now(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil -> :ok
      _pid -> GenServer.cast(server, :reconcile_now)
    end
  end

  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @impl true
  def init(opts) do
    state = %{
      reconcile_interval_ms: reconcile_interval(opts),
      list_active_connections_fun:
        Keyword.get(
          opts,
          :list_active_connections_fun,
          &ModbusMqtt.Connections.list_active_connections_with_device_fields/0
        ),
      start_connection_fun:
        Keyword.get(
          opts,
          :start_connection_fun,
          &ModbusMqtt.Engine.Supervisor.start_connection/1
        ),
      stop_connection_fun:
        Keyword.get(
          opts,
          :stop_connection_fun,
          &ModbusMqtt.Engine.Supervisor.stop_connection/1
        ),
      whereis_connection_supervisor_fun:
        Keyword.get(
          opts,
          :whereis_connection_supervisor_fun,
          &ModbusMqtt.Engine.ConnectionSupervisor.whereis/1
        ),
      connection_signatures: %{},
      debounce_timer: nil
    }

    send(self(), :reconcile)
    {:ok, schedule_next_reconcile(state)}
  end

  @impl true
  def handle_info(:reconcile, state) do
    next_state = reconcile(%{state | debounce_timer: nil})
    {:noreply, schedule_next_reconcile(next_state)}
  end

  @impl true
  def handle_info(:debounced_reconcile, state) do
    next_state = reconcile(%{state | debounce_timer: nil})
    {:noreply, next_state}
  end

  @impl true
  def handle_cast(:reconcile_now, %{debounce_timer: nil} = state) do
    timer = Process.send_after(self(), :debounced_reconcile, @debounce_ms)
    {:noreply, %{state | debounce_timer: timer}}
  end

  def handle_cast(:reconcile_now, state) do
    # A debounce timer is already pending — discard this request
    {:noreply, state}
  end

  defp reconcile(state) do
    connections = state.list_active_connections_fun.()
    desired_ids = MapSet.new(Enum.map(connections, & &1.id))

    Logger.debug("Engine reconciler evaluating #{length(connections)} active connection(s)")

    Enum.each(Map.keys(state.connection_signatures), fn connection_id ->
      if not MapSet.member?(desired_ids, connection_id) do
        stop_connection_if_running(state, connection_id, "inactive or removed")
      end
    end)

    Enum.each(connections, fn connection ->
      ensure_connection_tree(state, connection)
    end)

    next_signatures =
      Map.new(connections, fn connection ->
        {connection.id, connection_signature(connection)}
      end)

    %{state | connection_signatures: next_signatures}
  end

  defp ensure_connection_tree(state, connection) do
    connection_id = connection.id
    desired_signature = connection_signature(connection)
    current_signature = Map.get(state.connection_signatures, connection_id)
    running_pid = state.whereis_connection_supervisor_fun.(connection_id)

    cond do
      is_nil(running_pid) ->
        start_connection(state, connection)

      is_nil(current_signature) ->
        :ok

      current_signature != desired_signature ->
        Logger.info("Engine config changed for #{connection.name}; restarting connection tree")
        stop_connection_if_running(state, connection_id, "configuration changed")
        start_connection(state, connection)

      true ->
        :ok
    end
  end

  defp start_connection(state, connection) do
    case state.start_connection_fun.(connection) do
      {:ok, _pid} ->
        Logger.info("Started Engine for connection #{connection.id}")

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, {:already_present, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start Engine for connection #{connection.id}: #{inspect(reason)}")
    end
  end

  defp stop_connection_if_running(state, connection_id, reason) do
    case state.whereis_connection_supervisor_fun.(connection_id) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        case state.stop_connection_fun.(pid) do
          :ok ->
            Logger.info("Stopped Engine for connection #{connection_id} (#{reason})")

          {:error, :not_found} ->
            :ok

          {:error, stop_reason} ->
            Logger.warning(
              "Failed to stop Engine for connection #{connection_id} (#{reason}): #{inspect(stop_reason)}"
            )
        end
    end
  end

  defp schedule_next_reconcile(%{reconcile_interval_ms: :manual} = state), do: state

  defp schedule_next_reconcile(%{reconcile_interval_ms: interval_ms} = state)
       when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :reconcile, interval_ms)
    state
  end

  defp reconcile_interval(opts) do
    Keyword.get(
      opts,
      :reconcile_interval_ms,
      Application.get_env(
        :modbus_mqtt,
        :engine_reconcile_interval_ms,
        @default_reconcile_interval_ms
      )
    )
  end

  defp connection_signature(connection) do
    fields_signature =
      connection.fields
      |> List.wrap()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&field_signature/1)

    %{
      id: connection.id,
      name: connection.name,
      protocol: connection.protocol,
      base_topic: connection.base_topic,
      unit: connection.unit,
      transport_config: connection.transport_config || %{},
      fields: fields_signature
    }
  end

  defp field_signature(field) do
    %{
      id: field.id,
      name: field.name,
      type: field.type,
      data_type: field.data_type,
      address: field.address,
      address_offset: field.address_offset,
      poll_interval_ms: field.poll_interval_ms,
      scale: field.scale,
      swap_words: field.swap_words,
      swap_bytes: field.swap_bytes,
      value_semantics: field.value_semantics,
      enum_map: field.enum_map || %{},
      unit: Map.get(field, :unit)
    }
  end
end
