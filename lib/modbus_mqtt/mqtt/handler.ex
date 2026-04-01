defmodule ModbusMqtt.Mqtt.Handler do
  use Tortoise311.Handler
  require Logger

  alias ModbusMqtt.Devices
  alias ModbusMqtt.Engine.WriteQueue
  alias ModbusMqtt.Mqtt.Status
  alias ModbusMqtt.Mqtt.Topics

  def init(args) do
    {:ok,
     %{
       devices: Keyword.get(args, :devices, Devices),
       writer: Keyword.get(args, :writer, WriteQueue)
     }}
  end

  def connection(status, state) do
    Logger.info("MQTT bridge connection is #{status}")
    Status.mqtt_connection_changed(status)
    {:ok, state}
  end

  def handle_message(topic, payload, state) do
    with {:ok, {device_topic, field_topic}} <- Topics.parse_set_topic(topic),
         {device, field} <- state.devices.find_active_field_by_topic(device_topic, field_topic),
         {:ok, value} <- decode_payload(payload),
         :ok <- state.writer.write(device, field, value) do
      Logger.info("Applied MQTT write for #{device.name}:#{field.name} to #{inspect(value)}")
    else
      {:error, :not_set_topic} ->
        :ok

      nil ->
        Logger.warning("Ignoring MQTT write for unknown field topic #{inspect(topic)}")

      {:error, reason} ->
        Logger.error("Failed MQTT write for #{inspect(topic)}: #{inspect(reason)}")
    end

    {:ok, state}
  end

  def subscription(status, topic_filter, state) do
    Logger.info("MQTT subscription #{topic_filter} is #{inspect(status)}")
    {:ok, state}
  end

  def terminate(reason, _state) do
    Logger.warning("MQTT handler terminating: #{inspect(reason)}")
    :ok
  end

  defp decode_payload(payload) when is_binary(payload) do
    trimmed = String.trim(payload)

    case Jason.decode(trimmed) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, trimmed}
    end
  end

  defp decode_payload(payload), do: {:ok, payload}
end
