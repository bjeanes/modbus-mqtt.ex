defmodule ModbusMqtt.Engine.Hub do
  @moduledoc """
  A centralized cache for the latest Modbus register readings.
  Also serves as the traffic-cop for outbound data, dropping duplicate
  readings to prevent flooding the MQTT broker and internal PubSub menus.
  """
  use GenServer
  require Logger

  alias ModbusMqtt.Engine.FieldSemantics
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
  def put_value(%{id: _device_id} = device, %{name: _field_name} = field, reading) do
    put_value(__MODULE__, device, field, reading)
  end

  def put_value(server, %{id: _device_id} = device, %{name: _field_name} = field, reading) do
    GenServer.cast(server, {:put_value, device, field, reading})
  end

  @doc "Retrieves the latest known state map of %{field_name => value} for an entire device"
  def get_device_state(device_id) do
    get_device_state(@table, device_id)
  end

  def get_device_state(table, device_id) do
    get_device_readings(table, device_id)
    |> Map.new(fn {field_name, reading} -> {field_name, reading.value} end)
  end

  @doc "Retrieves the latest known reading map for an entire device"
  def get_device_readings(device_id) do
    get_device_readings(@table, device_id)
  end

  def get_device_readings(table, device_id) do
    # Search ETS for all keys matching {device_id, _}
    match_spec = [{{{device_id, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}]

    :ets.select(table, match_spec)
    |> Enum.map(fn {field_name, reading, updated_at} ->
      {field_name, %{value: reading.value, formatted: reading.formatted, updated_at: updated_at}}
    end)
    |> Map.new()
  end

  @doc "Retrieves the latest known reading for a single field on a device"
  def get_field_reading(device_id, field_name) do
    get_field_reading(@table, device_id, field_name)
  end

  def get_field_reading(table, device_id, field_name) do
    key = {device_id, field_name}

    case :ets.lookup(table, key) do
      [{^key, reading, updated_at}] ->
        %{value: reading.value, formatted: reading.formatted, updated_at: updated_at}

      [] ->
        nil
    end
  end

  @impl true
  def handle_cast({:put_value, device, field, reading}, state) do
    key = {device.id, field.name}

    normalized_reading = normalize_reading(reading)

    changed? =
      case :ets.lookup(state.table, key) do
        [{^key, existing_reading, _updated_at}] ->
          existing_reading.bytes != normalized_reading.bytes

        [] ->
          true
      end

    if changed? do
      # 1. Update ETS
      :ets.insert(state.table, {key, normalized_reading, state.now_fun.()})

      # 2. Phoenix PubSub Broadcast for Real-Time Web UI
      state.broadcast_fun.(ModbusMqtt.PubSub, device.id, field.name, normalized_reading.value)

      # 3. Publish out to Tortoise311
      topic = Topics.device_value_topic(device, field)
      state.publish_fun.(topic, FieldSemantics.format(normalized_reading.value), [])

      detail_topic = Topics.device_value_detail_topic(device, field)

      detail_payload =
        Jason.encode!(%{
          "bytes" => normalized_reading.bytes,
          "decoded" => json_value(normalized_reading.decoded),
          "value" => json_value(normalized_reading.value)
        })

      state.publish_fun.(detail_topic, detail_payload, [])

      Logger.debug(
        "Hub Delta: #{device.name}:#{field.name} changed to #{normalized_reading.formatted}"
      )
    end

    {:noreply, state}
  end

  defp normalize_reading(%{bytes: bytes, decoded: decoded, value: value, formatted: formatted}) do
    %{bytes: bytes, decoded: decoded, value: value, formatted: formatted}
  end

  defp normalize_reading(%{bytes: bytes, value: value, formatted: formatted}) do
    %{bytes: bytes, decoded: value, value: value, formatted: formatted}
  end

  defp normalize_reading(value) do
    %{bytes: [], decoded: value, value: value, formatted: FieldSemantics.format(value)}
  end

  defp json_value(%Decimal{} = value), do: Jason.Fragment.new(Decimal.to_string(value, :normal))
  defp json_value(value), do: value

  def publish_mqtt(topic, payload, opts) do
    ModbusMqtt.Mqtt.Supervisor.publish(topic, payload, opts)
  end

  def broadcast_update(pubsub, device_id, field_name, value) do
    Phoenix.PubSub.broadcast!(
      pubsub,
      "device:#{device_id}",
      {:field_update, field_name, value}
    )
  end
end
