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
  def put_value(%{id: _device_id} = device, %{name: _register_name} = register, reading) do
    put_value(__MODULE__, device, register, reading)
  end

  def put_value(server, %{id: _device_id} = device, %{name: _register_name} = register, reading) do
    GenServer.cast(server, {:put_value, device, register, reading})
  end

  @doc "Retrieves the latest known state map of %{register_name => value} for an entire device"
  def get_device_state(device_id) do
    get_device_state(@table, device_id)
  end

  def get_device_state(table, device_id) do
    # Search ETS for all keys matching {device_id, _}
    match_spec = [{{{device_id, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}]

    :ets.select(table, match_spec)
    |> Enum.map(fn {register_name, reading} ->
      {register_name, reading.value}
    end)
    |> Map.new()
  end

  @impl true
  def handle_cast({:put_value, device, register, reading}, state) do
    key = {device.id, register.name}

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
      state.broadcast_fun.(ModbusMqtt.PubSub, device.id, register.name, normalized_reading.value)

      # 3. Publish out to Tortoise311
      topic = Topics.device_value_topic(device, register)
      state.publish_fun.(topic, normalized_reading.formatted, [])

      detail_topic = Topics.device_value_detail_topic(device, register)

      detail_payload =
        Jason.encode!(%{"bytes" => normalized_reading.bytes, "value" => normalized_reading.value})

      state.publish_fun.(detail_topic, detail_payload, [])

      Logger.debug(
        "Hub Delta: #{device.name}:#{register.name} changed to #{normalized_reading.formatted}"
      )
    end

    {:noreply, state}
  end

  defp normalize_reading(%{bytes: bytes, value: value, formatted: formatted}) do
    %{bytes: bytes, value: value, formatted: formatted}
  end

  defp normalize_reading(value) do
    %{bytes: [], value: value, formatted: to_string(value)}
  end

  def publish_mqtt(topic, payload, opts) do
    ModbusMqtt.Mqtt.Supervisor.publish(topic, payload, opts)
  end

  def broadcast_update(pubsub, device_id, register_name, value) do
    Phoenix.PubSub.broadcast!(
      pubsub,
      "device:#{device_id}",
      {:register_update, register_name, value}
    )
  end
end
