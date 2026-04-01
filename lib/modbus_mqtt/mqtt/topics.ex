defmodule ModbusMqtt.Mqtt.Topics do
  @moduledoc """
  Centralized helpers for MQTT topic construction.
  """

  alias ModbusMqtt.Devices.Topic

  @devices_segment "devices"
  @status_segment "status"
  @detail_segment "detail"
  @set_segment "set"
  @last_error_segment "last_error"

  def base_topic do
    Application.fetch_env!(:modbus_mqtt, :mqtt)
    |> Keyword.fetch!(:base_topic)
    |> to_string()
    |> String.trim("/")
  end

  def normalize_base_segments(base) when is_binary(base) do
    String.split(base, "/", trim: true)
  end

  def normalize_base_segments(base_segments) when is_list(base_segments) do
    if Enum.all?(base_segments, &is_binary/1) do
      Enum.reject(base_segments, &(&1 == ""))
    else
      base_topic_segments()
    end
  end

  def normalize_base_segments(_base), do: base_topic_segments()

  def bridge_status_topic do
    join([base_topic(), @status_segment])
  end

  def device_value_topic(device, field) do
    join(device_field_topic_parts(device, field))
  end

  def device_value_detail_topic(device, field) do
    join(device_field_topic_parts(device, field) ++ [@detail_segment])
  end

  def device_value_set_topic(device, field) do
    join(device_field_topic_parts(device, field) ++ [@set_segment])
  end

  def device_value_set_topic_filter do
    join([base_topic(), "+", "+", @set_segment])
  end

  def device_status_topic(device_meta) do
    join(device_meta_topic_parts(device_meta) ++ [@status_segment])
  end

  def device_last_error_topic(device_meta) do
    join(device_meta_topic_parts(device_meta) ++ [@last_error_segment])
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
    parse_set_topic(topic, base_segments: base_topic_segments())
  end

  def parse_set_topic(topic, opts) when is_list(opts) do
    base_segments =
      opts
      |> Keyword.get(:base_segments, base_topic())
      |> normalize_base_segments()

    with {:ok, incoming_segments} <- normalize_topic_segments(topic),
         {^base_segments, [device_topic, field_topic, @set_segment]} <-
           Enum.split(incoming_segments, length(base_segments)) do
      {:ok, {device_topic, field_topic}}
    else
      _ -> {:error, :not_set_topic}
    end
  end

  defp normalize_topic_segments(topic) when is_binary(topic) do
    {:ok, String.split(topic, "/", trim: true)}
  end

  defp normalize_topic_segments(topic_levels) when is_list(topic_levels) do
    cond do
      Enum.all?(topic_levels, &is_binary/1) ->
        {:ok, topic_levels}

      Enum.all?(topic_levels, &is_integer/1) and List.ascii_printable?(topic_levels) ->
        normalize_topic_segments(to_string(topic_levels))

      true ->
        {:error, :not_set_topic}
    end
  end

  defp normalize_topic_segments(_topic), do: {:error, :not_set_topic}

  defp base_topic_segments do
    base_topic()
    |> normalize_base_segments()
  end

  defp device_field_topic_parts(device, field) do
    [base_topic(), Topic.key(device), field.name]
  end

  defp device_meta_topic_parts(device_meta) do
    [base_topic(), @devices_segment, Topic.key(device_meta)]
  end
end
