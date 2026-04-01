defmodule ModbusMqtt.Engine.Reconciler do
  @moduledoc """
  Continuously reconciles active device definitions from the database with the
  running per-device engine supervisor trees.

  Responsibilities:
  - Start missing device trees for active devices.
  - Stop running trees that are no longer active.
  - Restart running trees when device/register definitions change.
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
      list_active_devices_fun:
        Keyword.get(
          opts,
          :list_active_devices_fun,
          &ModbusMqtt.Devices.list_active_devices_with_fields/0
        ),
      start_device_fun:
        Keyword.get(opts, :start_device_fun, &ModbusMqtt.Engine.Supervisor.start_device/1),
      stop_device_fun:
        Keyword.get(opts, :stop_device_fun, &ModbusMqtt.Engine.Supervisor.stop_device/1),
      whereis_device_supervisor_fun:
        Keyword.get(
          opts,
          :whereis_device_supervisor_fun,
          &ModbusMqtt.Engine.DeviceSupervisor.whereis/1
        ),
      device_signatures: %{},
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
    devices = state.list_active_devices_fun.()
    desired_ids = MapSet.new(Enum.map(devices, & &1.id))

    Logger.debug("Engine reconciler evaluating #{length(devices)} active device(s)")

    Enum.each(Map.keys(state.device_signatures), fn device_id ->
      if not MapSet.member?(desired_ids, device_id) do
        stop_device_if_running(state, device_id, "inactive or removed")
      end
    end)

    Enum.each(devices, fn device ->
      ensure_device_tree(state, device)
    end)

    next_signatures =
      Map.new(devices, fn device ->
        {device.id, device_signature(device)}
      end)

    %{state | device_signatures: next_signatures}
  end

  defp ensure_device_tree(state, device) do
    device_id = device.id
    desired_signature = device_signature(device)
    current_signature = Map.get(state.device_signatures, device_id)
    running_pid = state.whereis_device_supervisor_fun.(device_id)

    cond do
      is_nil(running_pid) ->
        start_device(state, device)

      is_nil(current_signature) ->
        :ok

      current_signature != desired_signature ->
        Logger.info("Engine config changed for #{device.name}; restarting device tree")
        stop_device_if_running(state, device_id, "configuration changed")
        start_device(state, device)

      true ->
        :ok
    end
  end

  defp start_device(state, device) do
    case state.start_device_fun.(device) do
      {:ok, _pid} ->
        Logger.info("Started Engine for #{device.name}")

      {:error, {:already_started, _pid}} ->
        :ok

      {:error, {:already_present, _pid}} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to start Engine for #{device.name}: #{inspect(reason)}")
    end
  end

  defp stop_device_if_running(state, device_id, reason) do
    case state.whereis_device_supervisor_fun.(device_id) do
      nil ->
        :ok

      pid when is_pid(pid) ->
        case state.stop_device_fun.(pid) do
          :ok ->
            Logger.info("Stopped Engine for device #{device_id} (#{reason})")

          {:error, :not_found} ->
            :ok

          {:error, stop_reason} ->
            Logger.warning(
              "Failed to stop Engine for device #{device_id} (#{reason}): #{inspect(stop_reason)}"
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

  defp device_signature(device) do
    fields_signature =
      device.fields
      |> List.wrap()
      |> Enum.sort_by(& &1.id)
      |> Enum.map(&field_signature/1)

    %{
      id: device.id,
      name: device.name,
      protocol: device.protocol,
      base_topic: device.base_topic,
      unit: device.unit,
      transport_config: device.transport_config || %{},
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
