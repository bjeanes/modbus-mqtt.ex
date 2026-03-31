defmodule ModbusMqtt.Engine.RegisterReadingTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Engine.RegisterReading

  test "builds bytes/decoded/value/formatted for holding registers" do
    register = %{
      type: :holding_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = RegisterReading.from_modbus([0x1234], register)

    assert reading.bytes == [0x12, 0x34]
    assert reading.decoded == 0x1234
    assert reading.value == 0x1234
    assert reading.formatted == "4660"
  end

  test "keeps bit reads as-is for coil/discrete input values" do
    register = %{
      type: :coil,
      data_type: :bool,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = RegisterReading.from_modbus([1], register)

    assert reading.bytes == [1]
    assert reading.decoded == true
    assert reading.value == true
    assert reading.formatted == "true"
  end

  test "keeps bytes as read while swap_words and swap_bytes affect interpreted float value" do
    register = %{
      type: :input_register,
      data_type: :float32,
      scale: 0,
      swap_words: true,
      swap_bytes: true,
      value_semantics: :raw,
      enum_map: %{}
    }

    reading = RegisterReading.from_modbus([0x0000, 0x803F], register)

    assert reading.bytes == [0x00, 0x00, 0x80, 0x3F]
    assert reading.decoded == 1.0
    assert reading.value == 1.0
    assert reading.formatted == "1.0"
  end

  test "swap_bytes changes interpreted value but not raw byte capture" do
    base_register = %{
      type: :holding_register,
      data_type: :uint32,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }

    swapped_register = %{base_register | swap_bytes: true}

    base_reading = RegisterReading.from_modbus([0x1234, 0x5678], base_register)
    swapped_reading = RegisterReading.from_modbus([0x1234, 0x5678], swapped_register)

    assert base_reading.bytes == [0x12, 0x34, 0x56, 0x78]
    assert swapped_reading.bytes == [0x12, 0x34, 0x56, 0x78]

    assert base_reading.decoded == 0x12345678
    assert swapped_reading.decoded == 0x34127856
    assert base_reading.value == 0x12345678
    assert swapped_reading.value == 0x34127856
    assert swapped_reading.formatted == Integer.to_string(0x34127856)
  end

  test "maps uint16 enum values to semantic strings" do
    register = %{
      type: :input_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :enum,
      enum_map: %{"1" => "standby", "0xAA" => "maintenance", "0b11" => "running"}
    }

    reading = RegisterReading.from_modbus([0x00AA], register)

    assert reading.bytes == [0x00, 0xAA]
    assert reading.decoded == 170
    assert reading.value == "maintenance"
    assert reading.formatted == "maintenance"
  end
end
