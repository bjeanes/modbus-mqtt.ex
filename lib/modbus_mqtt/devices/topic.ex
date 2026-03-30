defmodule ModbusMqtt.Devices.Topic do
  @moduledoc """
  Helpers for deriving and validating the MQTT topic segment used for a device.
  """

  import Ecto.Changeset

  @segment_pattern ~r/^[^\/#\+\s]+$/

  def key(%{base_topic: base_topic, id: id}) do
    case normalize(base_topic) do
      nil -> to_string(id)
      segment -> segment
    end
  end

  def normalize(nil), do: nil

  def normalize(value) do
    value
    |> to_string()
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def validate_segment(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case normalize(value) do
        nil ->
          []

        segment ->
          if Regex.match?(@segment_pattern, segment) do
            []
          else
            [{field, "must be a single MQTT topic segment without wildcards or slashes"}]
          end
      end
    end)
  end
end
