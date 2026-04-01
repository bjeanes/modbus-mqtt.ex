defmodule ModbusMqtt.Mqtt.Handler do
  use Tortoise311.Handler
  require Logger

  alias ModbusMqtt.Devices
  alias ModbusMqtt.Engine.WriteQueue
  alias ModbusMqtt.Mqtt.HomeAssistant
  alias ModbusMqtt.Mqtt.Status
  alias ModbusMqtt.Mqtt.Topics

  def init(args) do
    base_segments =
      args
      |> Keyword.get(:base_segments, Topics.base_topic())
      |> Topics.normalize_base_segments()

    {:ok,
     %{
       devices: Keyword.get(args, :devices, Devices),
       writer: Keyword.get(args, :writer, WriteQueue),
       base_segments: base_segments,
       home_assistant: Keyword.get(args, :home_assistant, HomeAssistant)
     }}
  end

  def connection(status, state) do
    Logger.info("MQTT bridge connection is #{status}")
    Status.mqtt_connection_changed(status)
    state.home_assistant.mqtt_connection_changed(status)
    {:ok, state}
  end

  def handle_message(topic, payload, state) do
    maybe_handle_home_assistant_status(topic, payload, state.home_assistant)

    case process_message(topic, payload, state) do
      {:queued, device, field, value} ->
        Logger.info("Queued MQTT write for #{device.name}:#{field.name} to #{inspect(value)}")

      {:ignored, :not_set_topic} ->
        :ok

      {:ignored, :unknown_field} ->
        Logger.warning("Ignoring MQTT write for unknown field topic #{inspect(topic)}")

      {:error, reason} ->
        Logger.error("Failed to queue MQTT write for #{inspect(topic)}: #{inspect(reason)}")
    end

    {:ok, state}
  end

  defp maybe_handle_home_assistant_status(topic, payload, home_assistant) do
    topic_string = normalize_topic(topic)
    payload_string = normalize_payload(payload)

    if topic_string == Topics.home_assistant_status_topic() and payload_string == "online" do
      home_assistant.home_assistant_online()
    end
  end

  defp normalize_topic(topic) when is_binary(topic), do: topic

  defp normalize_topic(topic_levels) when is_list(topic_levels) do
    topic_levels
    |> Enum.map(&to_string/1)
    |> Enum.join("/")
  end

  defp normalize_topic(_topic), do: ""

  defp normalize_payload(payload) when is_binary(payload), do: String.trim(payload)
  defp normalize_payload(payload), do: to_string(payload) |> String.trim()

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

  defp process_message(topic, payload, state) do
    with {:ok, {device_topic, field_topic}} <-
           Topics.parse_set_topic(topic, base_segments: state.base_segments),
         {device, field} <- state.devices.find_active_field_by_topic(device_topic, field_topic),
         {:ok, value} <- decode_payload(payload),
         :ok <- state.writer.write(device, field, value) do
      {:queued, device, field, value}
    else
      {:error, :not_set_topic} -> {:ignored, :not_set_topic}
      nil -> {:ignored, :unknown_field}
      {:error, reason} -> {:error, reason}
    end
  end
end
