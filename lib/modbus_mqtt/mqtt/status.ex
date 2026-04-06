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

  def device_connecting(connection) do
    device_connecting(__MODULE__, connection)
  end

  def device_connecting(server, connection) do
    set_device_status(server, connection, "connecting")
  end

  def device_retrying_connection(connection, attempt) do
    device_retrying_connection(__MODULE__, connection, attempt)
  end

  def device_retrying_connection(server, connection, _attempt) do
    GenServer.cast(server, {:device_state, connection, "retrying_connection", nil})
  end

  def device_connected(connection) do
    device_connected(__MODULE__, connection)
  end

  def device_connected(server, connection) do
    GenServer.cast(server, {:device_state, connection, "online", nil})
  end

  def device_connection_failed(connection, error_message) when is_binary(error_message) do
    device_connection_failed(__MODULE__, connection, error_message)
  end

  def device_connection_failed(server, connection, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_state, connection, "connection_failed", error_message})
  end

  def device_disconnected(connection, error_message \\ nil)

  def device_disconnected(connection, nil) do
    device_disconnected(__MODULE__, connection, nil)
  end

  def device_disconnected(connection, error_message) when is_binary(error_message) do
    device_disconnected(__MODULE__, connection, error_message)
  end

  def device_disconnected(server, connection, nil) do
    GenServer.cast(server, {:device_state, connection, "offline", :keep})
  end

  def device_disconnected(server, connection, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_state, connection, "offline", error_message})
  end

  def device_error(connection, error_message) when is_binary(error_message) do
    device_error(__MODULE__, connection, error_message)
  end

  def device_error(server, connection, error_message) when is_binary(error_message) do
    GenServer.cast(server, {:device_error, connection, error_message})
  end

  def clear_device_error(connection) do
    clear_device_error(__MODULE__, connection)
  end

  def clear_device_error(server, connection) do
    GenServer.cast(server, {:clear_device_error, connection})
  end

  def connection_status(connection, opts \\ []) do
    connection_status(__MODULE__, connection, opts)
  end

  def connection_status(server, %{id: _id, base_topic: _base_topic} = connection, opts)
      when is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout, 100)

    case GenServer.whereis(server) do
      nil ->
        nil

      _pid ->
        try do
          GenServer.call(server, {:connection_status, connection}, timeout_ms)
        catch
          :exit, _reason -> nil
        end
    end
  end

  @impl true
  def init(opts) do
    publish_fun = Keyword.get(opts, :publish_fun, &__MODULE__.publish_mqtt/3)

    {:ok,
     %{
       mqtt_connected?: false,
       bridge_status: @bridge_offline,
       connections: %{},
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

  def handle_cast({:device_state, connection, status, error_update}, state) do
    {next_state, updates} = update_device_entry(state, connection, status, error_update)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  def handle_cast({:device_error, connection, error_message}, state) do
    {next_state, updates} = update_device_entry(state, connection, :keep, error_message)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  def handle_cast({:clear_device_error, connection}, state) do
    {next_state, updates} = update_device_entry(state, connection, :keep, nil)
    maybe_publish_updates(next_state, updates)
    {:noreply, next_state}
  end

  @impl true
  def handle_call({:connection_status, connection}, _from, state) do
    connection_key = Topic.key(connection)

    status =
      state.connections
      |> Map.get(connection_key)
      |> case do
        nil -> nil
        entry -> entry.status
      end

    {:reply, status, state}
  end

  defp set_device_status(server, connection, status) do
    GenServer.cast(server, {:device_state, connection, status, :keep})
  end

  defp update_device_entry(state, connection, status_update, error_update) do
    connection_key = Topic.key(connection)

    connection_meta = %{
      id: connection.id,
      name: connection.name,
      base_topic: connection.base_topic
    }

    entry =
      Map.get(state.connections, connection_key, %{
        connection: connection_meta,
        status: nil,
        last_error: nil
      })

    next_status = if status_update == :keep, do: entry.status, else: status_update

    next_error =
      case error_update do
        :keep -> entry.last_error
        value -> value
      end

    next_entry = %{
      entry
      | connection: connection_meta,
        status: next_status,
        last_error: next_error
    }

    updates =
      []
      |> maybe_add_update(:status, entry.status, next_entry.status, connection_meta)
      |> maybe_add_update(:last_error, entry.last_error, next_entry.last_error, connection_meta)

    {%{state | connections: Map.put(state.connections, connection_key, next_entry)}, updates}
  end

  defp maybe_add_update(updates, _field, old_value, new_value, _connection_meta)
       when old_value == new_value do
    updates
  end

  defp maybe_add_update(updates, field, _old_value, new_value, connection_meta) do
    [{field, connection_meta, new_value} | updates]
  end

  defp maybe_publish_updates(%{mqtt_connected?: false}, _updates), do: :ok

  defp maybe_publish_updates(state, updates) do
    Enum.each(updates, &publish_device_update(&1, state))
  end

  defp publish_device_snapshots(state) do
    Enum.each(state.connections, fn {_key, entry} ->
      if entry.status do
        publish_retained(state, Topics.device_status_topic(entry.connection), entry.status)
      end

      publish_retained(state, Topics.device_last_error_topic(entry.connection), entry.last_error)
    end)
  end

  defp publish_device_update({:status, connection_meta, value}, state) do
    publish_retained(state, Topics.device_status_topic(connection_meta), value)
    broadcast_connection_status(connection_meta, value)
  end

  defp publish_device_update({:last_error, connection_meta, value}, state) do
    publish_retained(state, Topics.device_last_error_topic(connection_meta), value)
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

  defp broadcast_connection_status(connection_meta, status) do
    Phoenix.PubSub.broadcast(
      ModbusMqtt.PubSub,
      "device:#{connection_meta.id}",
      {:connection_status_changed, connection_meta.id, status}
    )
  end
end
