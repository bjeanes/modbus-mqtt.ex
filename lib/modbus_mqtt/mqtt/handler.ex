defmodule ModbusMqtt.Mqtt.Handler do
  use Tortoise311.Handler
  require Logger

  alias ModbusMqtt.Mqtt.Status

  def init(args) do
    {:ok, args}
  end

  def connection(status, state) do
    Logger.info("MQTT bridge connection is #{status}")
    Status.mqtt_connection_changed(status)
    {:ok, state}
  end

  def handle_message(_topic, _payload, state) do
    Logger.debug("Ignoring inbound MQTT message because write support is disabled")

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
end
