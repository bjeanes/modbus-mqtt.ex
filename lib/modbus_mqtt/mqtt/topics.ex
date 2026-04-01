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

  def device_value_topic(device, field) do
    join([base_topic(), Topic.key(device), field.name])
  end

  def device_value_detail_topic(device, field) do
    join([base_topic(), Topic.key(device), field.name, "detail"])
  end

  def device_value_set_topic(device, field) do
    join([base_topic(), Topic.key(device), field.name, "set"])
  end

  def device_value_set_topic_filter do
    join([base_topic(), "+", "+", "set"])
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

  @doc """
  Parses an incoming MQTT topic and returns `{:ok, {device_topic, field_topic}}` if it
  matches the `<base>/<device>/<field>/set` pattern, or `{:error, :not_set_topic}` otherwise.
  """
  def parse_set_topic(topic) do
    base_segments = String.split(base_topic(), "/", trim: true)

    with {:ok, incoming_segments} <- normalize_topic_segments(topic) do
      case Enum.split(incoming_segments, length(base_segments)) do
        {^base_segments, [device_topic, field_topic, "set"]} ->
          {:ok, {device_topic, field_topic}}

        _ ->
          {:error, :not_set_topic}
      end
    end
  end

  defp normalize_topic_segments(topic) when is_binary(topic) do
    {:ok, String.split(topic, "/", trim: true)}
  end

  defp normalize_topic_segments(topic_levels) when is_list(topic_levels) do
    cond do
      Enum.all?(topic_levels, &is_binary/1) ->
        {:ok, topic_levels}

      Enum.all?(topic_levels, &is_integer/1) ->
        {:ok, topic_levels |> List.to_string() |> String.split("/", trim: true)}

      true ->
        {:error, :not_set_topic}
    end
  end

  defp normalize_topic_segments(_topic), do: {:error, :not_set_topic}
end
