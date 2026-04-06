defmodule ModbusMqtt.Mqtt.HomeAssistant do
  @moduledoc """
  Publishes Home Assistant MQTT discovery payloads for active connection fields.
  """

  use GenServer
  require Logger

  alias ModbusMqtt.Connections
  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Mqtt.Topics

  @project_device_identifier_prefix "modbus-mqtt-device"

  @numeric_data_types [:int16, :uint16, :int32, :uint32, :float32]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def mqtt_connection_changed(status) when status in [:up, :down] do
    mqtt_connection_changed(__MODULE__, status)
  end

  def mqtt_connection_changed(server, status) when status in [:up, :down] do
    GenServer.cast(server, {:mqtt_connection_changed, status})
  end

  def home_assistant_online do
    home_assistant_online(__MODULE__)
  end

  def home_assistant_online(server) do
    GenServer.cast(server, :home_assistant_online)
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       mqtt_connected?: false,
       connections_mod: Keyword.get(opts, :connections_mod, Connections),
       publish_fun: Keyword.get(opts, :publish_fun, &__MODULE__.publish_mqtt/3)
     }}
  end

  @impl true
  def handle_cast({:mqtt_connection_changed, :up}, state) do
    next_state = %{state | mqtt_connected?: true}
    publish_discovery(next_state)
    {:noreply, next_state}
  end

  def handle_cast({:mqtt_connection_changed, :down}, state) do
    {:noreply, %{state | mqtt_connected?: false}}
  end

  def handle_cast(:home_assistant_online, %{mqtt_connected?: true} = state) do
    publish_discovery(state)
    {:noreply, state}
  end

  def handle_cast(:home_assistant_online, state) do
    {:noreply, state}
  end

  defp publish_discovery(state) do
    state.connections_mod.list_active_connections_with_device_fields()
    |> Enum.each(fn connection ->
      Enum.each(connection.fields, fn field ->
        publish_field_discovery(state, connection, field)
      end)
    end)
  end

  defp publish_field_discovery(state, device, field) do
    component = field_component(field)
    topic = Topics.home_assistant_discovery_topic(component, discovery_object_id(device, field))
    payload = discovery_payload(device, field, component)

    case state.publish_fun.(topic, Jason.encode!(payload), []) do
      :ok ->
        :ok

      {:ok, _ref} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to publish HA discovery to #{topic}: #{inspect(reason)}")

      other ->
        Logger.warning("Unexpected HA discovery publish result for #{topic}: #{inspect(other)}")
    end
  end

  defp discovery_payload(device, field, component) do
    detail_topic = Topics.device_value_detail_topic(device, field)

    %{}
    |> Map.merge(common_payload(device, field, detail_topic))
    |> Map.merge(component_payload(device, field, component, detail_topic))
    |> maybe_put_unit(field)
  end

  defp common_payload(device, field, detail_topic) do
    %{
      "name" => field.name,
      "unique_id" => discovery_unique_id(device, field),
      "state_topic" => detail_topic,
      "json_attributes_topic" => detail_topic,
      "availability" => [
        %{"topic" => Topics.bridge_status_topic()},
        %{"topic" => Topics.device_status_topic(device)}
      ],
      "payload_available" => "online",
      "payload_not_available" => "offline",
      "device" => device_payload(device)
    }
  end

  defp component_payload(_device, _field, "binary_sensor", _detail_topic) do
    %{
      "value_template" => "{{ 'ON' if value_json.value else 'OFF' }}",
      "payload_on" => "ON",
      "payload_off" => "OFF"
    }
  end

  defp component_payload(device, field, "sensor", _detail_topic) do
    base = %{"value_template" => "{{ value_json.value }}"}

    if Field.writable?(field) do
      Map.put(base, "command_topic", Topics.device_value_set_topic(device, field))
    else
      base
    end
  end

  defp component_payload(device, field, "number", _detail_topic) do
    %{
      "value_template" => "{{ value_json.value }}",
      "command_topic" => Topics.device_value_set_topic(device, field),
      "mode" => "box"
    }
  end

  defp component_payload(device, field, "select", _detail_topic) do
    %{
      "value_template" => "{{ value_json.value }}",
      "command_topic" => Topics.device_value_set_topic(device, field),
      "options" => field_options(field)
    }
  end

  defp component_payload(device, field, "switch", _detail_topic) do
    %{
      "value_template" => "{{ 'ON' if value_json.value else 'OFF' }}",
      "command_topic" => Topics.device_value_set_topic(device, field),
      "payload_on" => "true",
      "payload_off" => "false",
      "state_on" => "ON",
      "state_off" => "OFF"
    }
  end

  defp maybe_put_unit(payload, field) do
    case normalized_unit(field.unit) do
      nil -> payload
      unit -> Map.put(payload, "unit_of_measurement", unit)
    end
  end

  defp normalized_unit(nil), do: nil

  defp normalized_unit(unit) when is_binary(unit) do
    trimmed = String.trim(unit)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalized_unit(_unit), do: nil

  defp field_component(field) do
    cond do
      Field.writable?(field) and bool_field?(field) -> "switch"
      Field.writable?(field) and enum_field?(field) -> "select"
      Field.writable?(field) and numeric_field?(field) -> "number"
      bool_field?(field) -> "binary_sensor"
      true -> "sensor"
    end
  end

  defp bool_field?(field) do
    field.type in [:coil, :discrete_input] or
      field.data_type == :bool or
      is_integer(field.bit_mask) or
      Field.enum_boolean?(field)
  end

  defp numeric_field?(field) do
    field.data_type in @numeric_data_types
  end

  defp enum_field?(field) do
    field.value_semantics == :enum
  end

  defp field_options(field) do
    field
    |> Map.get(:enum_map, %{})
    |> Enum.map(fn {_key, label} -> label end)
    |> Enum.uniq()
  end

  defp discovery_object_id(device, field) do
    "modbus_mqtt_#{device_key(device)}_#{field.name}"
  end

  defp discovery_unique_id(device, field) do
    "modbus_mqtt_#{device_key(device)}_#{field.name}"
  end

  defp device_key(device) do
    case device.base_topic do
      value when is_binary(value) and value != "" -> value
      _ -> Integer.to_string(device.id)
    end
  end

  defp device_payload(device) do
    identifiers = ["#{@project_device_identifier_prefix}-#{device.id}"]

    payload = %{
      "identifiers" => identifiers,
      "name" => device.name
    }

    case device_connection(device) do
      nil -> payload
      connection -> Map.put(payload, "connections", [connection])
    end
  end

  defp device_connection(device) do
    case get_in(device.transport_config || %{}, ["host"]) do
      host when is_binary(host) and host != "" -> ["ip", host]
      _ -> nil
    end
  end

  def publish_mqtt(topic, payload, opts) do
    ModbusMqtt.Mqtt.Supervisor.publish(topic, payload, opts)
  end
end
