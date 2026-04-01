defmodule ModbusMqtt.Engine.FieldCodec do
  @moduledoc """
  Pure helpers for decoding and scaling raw Modbus register values.
  """

  import Bitwise

  alias Decimal, as: D

  def word_count(%{data_type: :string, length: length}) when is_integer(length) and length > 0 do
    div(length + 1, 2)
  end

  def word_count(%{length: length}) when is_integer(length) and length > 0, do: length

  def word_count(%{data_type: data_type}), do: word_count(data_type)

  def word_count(:float32), do: 2
  def word_count(:int32), do: 2
  def word_count(:uint32), do: 2
  def word_count(_), do: 1

  def decode(values, field) do
    values
    |> parse_value(field.data_type, field.swap_words, field.swap_bytes)
    |> scale(field.scale)
    |> extract_bits(field)
  end

  def encode_write(value, %{type: :coil}) do
    with {:ok, normalized} <- normalize_coil(value) do
      {:ok, [normalized]}
    end
  end

  def encode_write(value, %{type: :holding_register} = field) do
    with {:ok, unscaled} <- unscale(value, field.scale),
         {:ok, values} <- encode_holding(unscaled, field) do
      {:ok, values}
    end
  end

  def encode_write(_value, %{type: type}), do: {:error, {:unsupported_write_type, type}}

  def scale(value, scale) when is_number(value) and scale != 0 do
    factor = scale_factor(scale)

    value
    |> to_decimal()
    |> D.mult(factor)
    |> D.normalize()
  end

  def scale(value, _scale), do: value

  defp scale_factor(scale) when scale > 0 do
    D.new(Integer.pow(10, scale))
  end

  defp scale_factor(scale) when scale < 0 do
    D.div(D.new(1), D.new(Integer.pow(10, -scale)))
  end

  defp to_decimal(value) when is_integer(value), do: D.new(value)
  defp to_decimal(value) when is_float(value), do: D.from_float(value)

  defp to_decimal(%Decimal{} = value), do: value

  defp to_decimal(value) when is_binary(value) do
    case D.parse(String.trim(value)) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  defp to_decimal(_value), do: nil

  def parse_value([value], :uint16, _, _), do: value

  def parse_value([value], :int16, _, _) do
    <<result::signed-16>> = <<value::16>>
    result
  end

  def parse_value([first, second], :float32, swap_words, swap_bytes) do
    <<float_value::float-32>> = ordered_binary(first, second, swap_words, swap_bytes)
    float_value
  end

  def parse_value([first, second], :uint32, swap_words, swap_bytes) do
    <<value::unsigned-32>> = ordered_binary(first, second, swap_words, swap_bytes)
    value
  end

  def parse_value([first, second], :int32, swap_words, swap_bytes) do
    <<value::signed-32>> = ordered_binary(first, second, swap_words, swap_bytes)
    value
  end

  def parse_value([1], :bool, _, _), do: true
  def parse_value([0], :bool, _, _), do: false

  def parse_value(values, :string, _, _) when is_list(values) do
    values
    |> Enum.flat_map(fn word -> [word >>> 8 &&& 0xFF, word &&& 0xFF] end)
    |> :binary.list_to_bin()
    |> String.trim_trailing(<<0>>)
  end

  def parse_value(values, _, _, _), do: values

  defp ordered_binary(first, second, swap_words, swap_bytes) do
    first_word = if swap_bytes, do: swap_16(first), else: first
    second_word = if swap_bytes, do: swap_16(second), else: second

    if swap_words do
      <<second_word::16, first_word::16>>
    else
      <<first_word::16, second_word::16>>
    end
  end

  defp swap_16(value) do
    <<byte_one, byte_two>> = <<value::16>>
    <<swapped::16>> = <<byte_two, byte_one>>
    swapped
  end

  defp extract_bits(decoded, %{bit_mask: bit_mask})
       when is_integer(bit_mask) and is_integer(decoded) do
    (decoded &&& bit_mask) != 0
  end

  defp extract_bits(decoded, _field), do: decoded

  defp unscale(value, 0), do: {:ok, value}

  defp unscale(value, scale) do
    case to_decimal(value) do
      nil ->
        {:error, :invalid_number}

      decimal_value ->
        factor = scale_factor(scale)
        {:ok, D.div(decimal_value, factor) |> D.normalize()}
    end
  end

  defp normalize_coil(value) when value in [true, 1], do: {:ok, 1}
  defp normalize_coil(value) when value in [false, 0], do: {:ok, 0}

  defp normalize_coil(value) when is_binary(value) do
    case String.trim(value) |> String.downcase() do
      "true" -> {:ok, 1}
      "false" -> {:ok, 0}
      "1" -> {:ok, 1}
      "0" -> {:ok, 0}
      _ -> {:error, :invalid_boolean}
    end
  end

  defp normalize_coil(_value), do: {:error, :invalid_boolean}

  defp encode_holding(value, %{data_type: :uint16}) do
    with {:ok, integer} <- decimal_to_integer(value),
         :ok <- ensure_in_range(integer, 0, 0xFFFF) do
      {:ok, [integer]}
    end
  end

  defp encode_holding(value, %{data_type: :int16}) do
    with {:ok, integer} <- decimal_to_integer(value),
         :ok <- ensure_in_range(integer, -0x8000, 0x7FFF) do
      <<word::unsigned-16>> = <<integer::signed-16>>
      {:ok, [word]}
    end
  end

  defp encode_holding(value, %{data_type: :uint32} = field) do
    with {:ok, integer} <- decimal_to_integer(value),
         :ok <- ensure_in_range(integer, 0, 0xFFFF_FFFF) do
      <<word1::16, word2::16>> = <<integer::unsigned-32>>
      {:ok, apply_swaps_32([word1, word2], field.swap_words, field.swap_bytes)}
    end
  end

  defp encode_holding(value, %{data_type: :int32} = field) do
    with {:ok, integer} <- decimal_to_integer(value),
         :ok <- ensure_in_range(integer, -0x8000_0000, 0x7FFF_FFFF) do
      <<word1::16, word2::16>> = <<integer::signed-32>>
      {:ok, apply_swaps_32([word1, word2], field.swap_words, field.swap_bytes)}
    end
  end

  defp encode_holding(value, %{data_type: :float32} = field) do
    with {:ok, float_value} <- to_float(value) do
      <<word1::16, word2::16>> = <<float_value::float-32>>
      {:ok, apply_swaps_32([word1, word2], field.swap_words, field.swap_bytes)}
    end
  end

  defp encode_holding(value, %{data_type: :bool}) do
    normalize_coil(value)
  end

  defp encode_holding(value, %{data_type: :string} = field) do
    with true <- is_binary(value) or {:error, :invalid_string},
         :ok <- ensure_string_length(value, field) do
      words = string_to_words(value, field.length)
      {:ok, words}
    end
  end

  defp encode_holding(_value, %{data_type: data_type}) do
    {:error, {:unsupported_data_type, data_type}}
  end

  defp decimal_to_integer(value) when is_integer(value), do: {:ok, value}

  defp decimal_to_integer(%Decimal{} = value) do
    normalized = D.normalize(value)

    if D.equal?(normalized, D.round(normalized, 0)) do
      {:ok, D.to_integer(normalized)}
    else
      {:error, :invalid_granularity}
    end
  end

  defp decimal_to_integer(value) when is_float(value) do
    decimal_to_integer(D.from_float(value))
  end

  defp decimal_to_integer(value) when is_binary(value) do
    case to_decimal(value) do
      nil -> {:error, :invalid_number}
      decimal -> decimal_to_integer(decimal)
    end
  end

  defp decimal_to_integer(_value), do: {:error, :invalid_number}

  defp to_float(value) when is_float(value), do: {:ok, value}
  defp to_float(value) when is_integer(value), do: {:ok, value * 1.0}

  defp to_float(%Decimal{} = value) do
    {:ok, Decimal.to_float(value)}
  end

  defp to_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_number}
    end
  end

  defp to_float(_value), do: {:error, :invalid_number}

  defp ensure_in_range(value, min, max) do
    if value >= min and value <= max do
      :ok
    else
      {:error, {:out_of_range, value, min, max}}
    end
  end

  defp apply_swaps_32([word1, word2], swap_words, swap_bytes) do
    words = if swap_words, do: [word2, word1], else: [word1, word2]

    if swap_bytes do
      Enum.map(words, &swap_16/1)
    else
      words
    end
  end

  defp ensure_string_length(value, %{length: length}) when is_integer(length) and length > 0 do
    if byte_size(value) <= length do
      :ok
    else
      {:error, {:string_too_long, byte_size(value), length}}
    end
  end

  defp ensure_string_length(_value, _field), do: {:error, :invalid_string_length}

  defp string_to_words(value, length) do
    padded = String.pad_trailing(value, length, <<0>>)
    bytes = :binary.bin_to_list(padded)

    bytes
    |> Enum.chunk_every(2, 2, [0])
    |> Enum.map(fn [high, low] -> (high <<< 8) + low end)
  end
end
