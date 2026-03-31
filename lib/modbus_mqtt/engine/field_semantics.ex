defmodule ModbusMqtt.Engine.FieldSemantics do
  @moduledoc """
  Converts decoded field primitives into semantic values and strings.
  """

  alias ModbusMqtt.Devices.Field

  def to_value(decoded, %{value_semantics: :enum} = field) do
    enum_value(decoded, field)
  end

  def to_value(decoded, _field), do: decoded

  def format(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def format(value) when is_binary(value), do: value
  def format(value), do: to_string(value)

  def normalized_enum_map(field) do
    field
    |> Map.get(:enum_map, %{})
    |> Enum.reduce(%{}, fn {key, label}, acc ->
      case Field.parse_enum_key(key) do
        {:ok, code} -> Map.put(acc, code, label)
        {:error, _reason} -> acc
      end
    end)
  end

  def from_value(value, %{value_semantics: :enum} = field) do
    reverse_map =
      field
      |> normalized_enum_map()
      |> Enum.reduce(%{}, fn {code, label}, acc -> Map.put(acc, label, code) end)

    case value do
      int_value when is_integer(int_value) ->
        {:ok, int_value}

      string_value when is_binary(string_value) ->
        trimmed = String.trim(string_value)

        case Map.fetch(reverse_map, trimmed) do
          {:ok, code} -> {:ok, code}
          :error -> Field.parse_enum_key(trimmed)
        end

      _ ->
        {:error, :invalid_enum_value}
    end
  end

  def from_value(value, _field), do: {:ok, value}

  defp enum_value(decoded, field) when is_integer(decoded) do
    normalized_enum_map(field)
    |> Map.get(decoded, Integer.to_string(decoded))
  end

  defp enum_value(decoded, _field), do: to_string(decoded)
end
