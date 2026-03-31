defmodule ModbusMqtt.Engine.RegisterValue do
  @moduledoc """
  Pure helpers for decoding and scaling raw Modbus register values.
  """

  alias Decimal, as: D

  def word_count(:float32), do: 2
  def word_count(:int32), do: 2
  def word_count(:uint32), do: 2
  def word_count(_), do: 1

  def decode(values, register) do
    values
    |> parse_value(register.data_type, register.swap_words, register.swap_bytes)
    |> scale(register.scale)
  end

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
end
