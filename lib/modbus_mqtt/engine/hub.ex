defmodule ModbusMqtt.Engine.Hub do
  @moduledoc """
  A centralized cache for the latest Modbus register readings.
  Also serves as the traffic-cop for outbound data, dropping duplicate
  readings to prevent flooding the MQTT broker and internal PubSub menus.
  """
  use GenServer
  require Logger

  alias ModbusMqtt.Mqtt.Topics

  @table :modbus_mqtt_hub_cache

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    # Public ETS table for lightning fast reads by LiveView if needed,
    # but writes iterate via the GenServer to serialize operations.
    table = Keyword.get(opts, :table, @table)
    publish_fun = Keyword.get(opts, :publish_fun, &__MODULE__.publish_mqtt/3)
    broadcast_fun = Keyword.get(opts, :broadcast_fun, &__MODULE__.broadcast_update/4)
    now_fun = Keyword.get(opts, :now_fun, &DateTime.utc_now/0)

    :ets.new(table, [:named_table, :set, :public, read_concurrency: true])

    {:ok,
     %{table: table, publish_fun: publish_fun, broadcast_fun: broadcast_fun, now_fun: now_fun}}
  end

  @doc """
  Pushes a new value to the Hub.
  If the raw bytes are different from the last known value, the Hub caches it,
  broadcasts internally via Phoenix.PubSub, and publishes to MQTT.
  """
  def put_value(%{id: _connection_id} = connection, %{name: _field_name} = field, reading) do
    put_value(__MODULE__, connection, field, reading)
  end

  def put_value(server, %{id: _connection_id} = connection, %{name: _field_name} = field, reading) do
    GenServer.cast(server, {:put_value, connection, field, reading})
  end

  @doc "Retrieves the latest known state map of %{field_name => value} for an entire device"
  def get_device_state(connection_id) do
    get_device_state(@table, connection_id)
  end

  def get_device_state(table, connection_id) do
    get_device_readings(table, connection_id)
    |> Map.new(fn {field_name, reading} -> {field_name, reading.value} end)
  end

  @doc "Retrieves the latest known reading map for an entire device"
  def get_device_readings(connection_id) do
    get_device_readings(@table, connection_id)
  end

  def get_device_readings(table, connection_id) do
    # Search ETS for all keys matching {connection_id, _}
    match_spec = [{{{connection_id, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}]

    :ets.select(table, match_spec)
    |> Enum.map(fn {field_name, reading, updated_at} ->
      {field_name, %{value: reading.value, formatted: reading.formatted, updated_at: updated_at}}
    end)
    |> Map.new()
  end

  @doc "Retrieves the latest known reading for a single field on a device"
  def get_field_reading(connection_id, field_name) do
    get_field_reading(@table, connection_id, field_name)
  end

  def get_field_reading(table, connection_id, field_name) do
    key = {connection_id, field_name}

    case :ets.lookup(table, key) do
      [{^key, reading, updated_at}] ->
        %{value: reading.value, formatted: reading.formatted, updated_at: updated_at}

      [] ->
        nil
    end
  end

  @impl true
  def handle_cast({:put_value, connection, field, %{bytes: bytes, value: value} = reading}, state) do
    key = {connection.id, field.name}

    changed? =
      case :ets.lookup(state.table, key) do
        [{^key, %{bytes: ^bytes, value: ^value}, _updated_at}] ->
          false

        _ ->
          true
      end

    # Always refresh cached reading and timestamp so the dashboard reflects
    # the latest computed state, even when outbound publish is suppressed.
    :ets.insert(state.table, {key, reading, state.now_fun.()})

    if changed? do
      # 2. Phoenix PubSub Broadcast for Real-Time Web UI
      state.broadcast_fun.(ModbusMqtt.PubSub, connection.id, field.name, reading.value)

      # 3. Publish out to Tortoise311
      topic = Topics.device_value_topic(connection, field)
      state.publish_fun.(topic, reading.formatted, [])

      detail_topic = Topics.device_value_detail_topic(connection, field)

      detail_payload =
        Jason.encode!(%{
          "bytes" => reading.bytes,
          "decoded" => json_value(reading.decoded),
          "formatted" => reading.formatted,
          "value" => json_value(reading.value)
        })

      state.publish_fun.(detail_topic, detail_payload, [])

      Logger.debug("Hub Delta: #{connection.name}:#{field.name} changed to #{reading.formatted}")
    end

    {:noreply, state}
  end

  defp json_value(%Decimal{} = value), do: Jason.Fragment.new(Decimal.to_string(value, :normal))
  defp json_value(value), do: value

  def publish_mqtt(topic, payload, opts) do
    ModbusMqtt.Mqtt.Supervisor.publish(topic, payload, opts)
  end

  def broadcast_update(pubsub, connection_id, field_name, value) do
    Phoenix.PubSub.broadcast!(
      pubsub,
      "device:#{connection_id}",
      {:field_update, field_name, value}
    )

    Phoenix.PubSub.broadcast!(
      pubsub,
      "device:#{connection_id}",
      {:field_value_changed, connection_id, field_name, value}
    )
  end
end
