defmodule ModbusMqtt.Mqtt.Topics do
  @moduledoc """
  Centralized helpers for MQTT topic construction.
  """

  alias ModbusMqtt.Devices.Topic

  def base_topic do
    Application.fetch_env!(:modbus_mqtt, :mqtt)
    |> Keyword.fetch!(:base_topic)
    |> to_string()
    |> String.trim("/")
  end

  def bridge_status_topic do
    join([base_topic(), "status"])
  end

  def device_value_topic(device, register) do
    join([base_topic(), Topic.key(device), register.name])
  end

  def device_value_detail_topic(device, register) do
    join([base_topic(), Topic.key(device), register.name, "detail"])
  end

  def device_status_topic(device_meta) do
    join([base_topic(), "devices", Topic.key(device_meta), "status"])
  end

  def device_last_error_topic(device_meta) do
    join([base_topic(), "devices", Topic.key(device_meta), "last_error"])
  end

  def join(parts) do
    parts
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("/")
  end
end
