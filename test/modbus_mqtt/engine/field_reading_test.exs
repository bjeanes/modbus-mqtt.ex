defmodule ModbusMqtt.Engine.FieldReadingTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Engine.FieldReading

  test "builds bytes/decoded/value/formatted for holding registers" do
    field = %{
      type: :holding_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = FieldReading.from_modbus([0x1234], field)

    assert reading.bytes == [0x12, 0x34]
    assert reading.decoded == 0x1234
    assert reading.value == 0x1234
    assert reading.formatted == "4660"
  end

  test "keeps bit reads as-is for coil/discrete input values" do
    field = %{
      type: :coil,
      data_type: :bool,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = FieldReading.from_modbus([1], field)

    assert reading.bytes == [1]
    assert reading.decoded == true
    assert reading.value == true
    assert reading.formatted == "true"
  end

  test "keeps bytes as read while swap_words and swap_bytes affect interpreted float value" do
    field = %{
      type: :input_register,
      data_type: :float32,
      scale: 0,
      swap_words: true,
      swap_bytes: true,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = FieldReading.from_modbus([0x0000, 0x803F], field)

    assert reading.bytes == [0x00, 0x00, 0x80, 0x3F]
    assert reading.decoded == 1.0
    assert reading.value == 1.0
    assert reading.formatted == "1.0"
  end

  test "swap_bytes changes interpreted value but not raw byte capture" do
    base_field = %{
      type: :holding_register,
      data_type: :uint32,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    swapped_field = %{base_field | swap_bytes: true}

    base_reading = FieldReading.from_modbus([0x1234, 0x5678], base_field)
    swapped_reading = FieldReading.from_modbus([0x1234, 0x5678], swapped_field)

    assert base_reading.bytes == [0x12, 0x34, 0x56, 0x78]
    assert swapped_reading.bytes == [0x12, 0x34, 0x56, 0x78]

    assert base_reading.decoded == 0x12345678
    assert swapped_reading.decoded == 0x34127856
    assert base_reading.value == 0x12345678
    assert swapped_reading.value == 0x34127856
    assert swapped_reading.formatted == Integer.to_string(0x34127856)
  end

  test "maps uint16 enum values to semantic strings" do
    field = %{
      type: :input_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :enum,
      enum_map: %{"1" => "standby", "0xAA" => "maintenance", "0b11" => "running"}
    }

    reading = FieldReading.from_modbus([0x00AA], field)

    assert reading.bytes == [0x00, 0xAA]
    assert reading.decoded == 170
    assert reading.value == "maintenance"
    assert reading.formatted == "maintenance"
  end

  test "bitmap field produces boolean reading from register word" do
    field = %{
      type: :input_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{},
      bit_mask: 0x0004
    }

    reading_true = FieldReading.from_modbus([0x000F], field)
    reading_false = FieldReading.from_modbus([0x0003], field)

    assert reading_true.decoded == true
    assert reading_true.value == true
    assert reading_true.formatted == "true"

    assert reading_false.decoded == false
    assert reading_false.value == false
    assert reading_false.formatted == "false"
  end
end
