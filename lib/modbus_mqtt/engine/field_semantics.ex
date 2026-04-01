defmodule ModbusMqtt.Engine.FieldSemantics do
  @moduledoc """
  Converts decoded field primitives into semantic values and strings.
  """

  alias ModbusMqtt.Devices.Field

  def to_value(decoded, %{value_semantics: :enum} = field) do
    case Field.enum_boolean_codes(field) do
      {:ok, %{true: true_code, false: false_code}} ->
        enum_boolean_value(decoded, true_code, false_code, field)

      :error ->
        enum_value(decoded, field)
    end
  end

  def to_value(decoded, _field), do: decoded

  def format(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  def format(value) when is_binary(value), do: value
  def format(value), do: to_string(value)

  def format(value, field) do
    if numeric_value?(value) do
      unformatted = format(value)

      case measurement_unit(field) do
        nil -> unformatted
        unit -> unformatted <> " " <> unit
      end
    else
      format(value)
    end
  end

  def normalized_enum_map(field) do
    (Map.get(field, :enum_map) || %{})
    |> Enum.reduce(%{}, fn {key, label}, acc ->
      case Field.parse_enum_key(key) do
        {:ok, code} -> Map.put(acc, code, label)
        {:error, _reason} -> acc
      end
    end)
  end

  def from_value(value, %{value_semantics: :enum} = field) do
    case Field.enum_boolean_codes(field) do
      {:ok, codes} ->
        enum_boolean_from_value(value, codes, field)

      :error ->
        from_enum_value(value, field)
    end
  end

  def from_value(value, _field), do: {:ok, value}

  defp enum_value(decoded, field) when is_integer(decoded) do
    normalized_enum_map(field)
    |> Map.get(decoded, Integer.to_string(decoded))
  end

  defp enum_value(decoded, _field), do: to_string(decoded)

  defp enum_boolean_value(decoded, true_code, _false_code, _field) when decoded == true_code,
    do: true

  defp enum_boolean_value(decoded, _true_code, false_code, _field) when decoded == false_code,
    do: false

  defp enum_boolean_value(decoded, _true_code, _false_code, field), do: enum_value(decoded, field)

  defp enum_boolean_from_value(value, codes, field) do
    case normalize_boolean_input(value) do
      {:ok, true} -> {:ok, Map.fetch!(codes, true)}
      {:ok, false} -> {:ok, Map.fetch!(codes, false)}
      :error -> from_enum_value(value, field)
    end
  end

  defp from_enum_value(value, field) do
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

  defp normalize_boolean_input(value) when value in [true, 1], do: {:ok, true}
  defp normalize_boolean_input(value) when value in [false, 0], do: {:ok, false}

  defp normalize_boolean_input(value) when is_binary(value) do
    case String.trim(value) |> String.downcase() do
      normalized when normalized in ["1", "true", "on", "enable", "enabled", "yes"] ->
        {:ok, true}

      normalized when normalized in ["0", "false", "off", "disable", "disabled", "no"] ->
        {:ok, false}

      _ ->
        :error
    end
  end

  defp normalize_boolean_input(_value), do: :error

  defp measurement_unit(%{unit: unit}) when is_binary(unit) do
    trimmed = String.trim(unit)

    if trimmed == "" do
      nil
    else
      trimmed
    end
  end

  defp measurement_unit(_field), do: nil

  defp numeric_value?(%Decimal{}), do: true
  defp numeric_value?(value) when is_integer(value), do: true
  defp numeric_value?(value) when is_float(value), do: true
  defp numeric_value?(_value), do: false
end
