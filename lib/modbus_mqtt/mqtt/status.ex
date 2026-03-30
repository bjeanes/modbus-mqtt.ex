defmodule ModbusMqtt.Mqtt.Status do
  use GenServer
  require Logger

  alias ModbusMqtt.Devices.Topic
  alias ModbusMqtt.Mqtt.Topics

  @bridge_online "online"
  @bridge_offline "offline"

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def bridge_status_topic do
    Topics.bridge_status_topic()
  end

  def mqtt_connection_changed(status) when status in [:up, :down] do
    mqtt_connection_changed(__MODULE__, status)
  end

  def mqtt_connection_changed(server, status) when status in [:up, :down] do
    GenServer.cast(server, {:mqtt_connection_changed, status})
  end

  def device_connecting(device) do
    device_connecting(__MODULE__, device)
  end

  def device_connecting(server, device) do
    set_device_status(server, device, "connecting")
  end

  def device_connected(device) do
    device_connected(__MODULE__, device)
  end

  def device_connected(server, device) do
    GenServer.cast(server, {:device_state, device, "online", nil})
  end

  def device_connection_failed(device, error_message) when is_binary(error_message) do
    device_connection_failed(__MODULE__, device, error_message)
  end

  def device_connection_failed(server, device, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_state, device, "connection_failed", error_message})
  end

  def device_disconnected(device, error_message \\ nil)

  def device_disconnected(device, nil) do
    device_disconnected(__MODULE__, device, nil)
  end

  def device_disconnected(device, error_message) when is_binary(error_message) do
    device_disconnected(__MODULE__, device, error_message)
  end

  def device_disconnected(server, device, nil) do
    GenServer.cast(server, {:device_state, device, "offline", :keep})
  end

  def device_disconnected(server, device, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_state, device, "offline", error_message})
  end

  def device_error(device, error_message) when is_binary(error_message) do
    device_error(__MODULE__, device, error_message)
  end

  def device_error(server, device, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_error, device, error_message})
  end

  def clear_device_error(device) do
    clear_device_error(__MODULE__, device)
  end

  def clear_device_error(server, device) do
    GenServer.cast(server, {:clear_device_error, device})
  end

  @impl true
  def init(opts) do
    publish_fun = Keyword.get(opts, :publish_fun, &__MODULE__.publish_mqtt/3)

    {:ok,
     %{
       mqtt_connected?: false,
       bridge_status: @bridge_offline,
       devices: %{},
       publish_fun: publish_fun
     }}
  end

  @impl true
  def handle_cast({:mqtt_connection_changed, :up}, state) do
    next_state = %{state | mqtt_connected?: true, bridge_status: @bridge_online}
    publish_bridge_status(next_state, @bridge_online)
    publish_device_snapshots(next_state)
    {:noreply, next_state}
  end

  def handle_cast({:mqtt_connection_changed, :down}, state) do
    {:noreply, %{state | mqtt_connected?: false, bridge_status: @bridge_offline}}
  end

  def handle_cast({:device_state, device, status, error_update}, state) do
    {next_state, updates} = update_device_entry(state, device, status, error_update)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  def handle_cast({:device_error, device, error_message}, state) do
    {next_state, updates} = update_device_entry(state, device, :keep, error_message)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  def handle_cast({:clear_device_error, device}, state) do
    {next_state, updates} = update_device_entry(state, device, :keep, nil)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  defp set_device_status(server, device, status) do
    GenServer.cast(server, {:device_state, device, status, :keep})
  end

  defp update_device_entry(state, device, status_update, error_update) do
    device_key = Topic.key(device)
    device_meta = %{id: device.id, name: device.name, base_topic: device.base_topic}

    entry =
      Map.get(state.devices, device_key, %{device: device_meta, status: nil, last_error: nil})

    next_status = if status_update == :keep, do: entry.status, else: status_update

    next_error =
      case error_update do
        :keep -> entry.last_error
        value -> value
      end

    next_entry = %{entry | device: device_meta, status: next_status, last_error: next_error}

    updates =
      []
      |> maybe_add_update(:status, entry.status, next_entry.status, device_meta)
      |> maybe_add_update(:last_error, entry.last_error, next_entry.last_error, device_meta)

    {%{state | devices: Map.put(state.devices, device_key, next_entry)}, updates}
  end

  defp maybe_add_update(updates, _field, old_value, new_value, _device_meta)
       when old_value == new_value do
    updates
  end

  defp maybe_add_update(updates, field, _old_value, new_value, device_meta) do
    [{field, device_meta, new_value} | updates]
  end

  defp maybe_publish_updates(%{mqtt_connected?: false}, _updates), do: :ok

  defp maybe_publish_updates(state, updates) do
    Enum.each(updates, &publish_device_update(&1, state))
  end

  defp publish_device_snapshots(state) do
    Enum.each(state.devices, fn {_key, entry} ->
      if entry.status do
        publish_retained(state, Topics.device_status_topic(entry.device), entry.status)
      end

      publish_retained(state, Topics.device_last_error_topic(entry.device), entry.last_error)
    end)
  end

  defp publish_device_update({:status, device_meta, value}, state) do
    publish_retained(state, Topics.device_status_topic(device_meta), value)
  end

  defp publish_device_update({:last_error, device_meta, value}, state) do
    publish_retained(state, Topics.device_last_error_topic(device_meta), value)
  end

  defp publish_bridge_status(state, value) do
    publish_retained(state, Topics.bridge_status_topic(), value)
  end

  defp publish_retained(state, topic, payload) do
    case state.publish_fun.(topic, payload, retain: true) do
      :ok ->
        :ok

      {:ok, _ref} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish MQTT status to #{topic}: #{inspect(reason)}")

      other ->
        Logger.warning("Unexpected MQTT publish result for #{topic}: #{inspect(other)}")
    end
  end

  def publish_mqtt(topic, payload, opts) do
    ModbusMqtt.Mqtt.Supervisor.publish(topic, payload, opts)
  end
end
