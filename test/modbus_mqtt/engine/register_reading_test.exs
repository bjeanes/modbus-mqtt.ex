defmodule ModbusMqtt.Engine.RegisterReadingTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Engine.RegisterReading

  test "builds bytes/value/formatted for holding registers" do
    register = %{
      type: :holding_register,
      data_type: :uint16,
      scale: 0,
      swap_words: false,
      swap_bytes: false
    }

    reading = RegisterReading.from_modbus([0x1234], register)

    assert reading.bytes == [0x12, 0x34]
    assert reading.value == 0x1234
    assert reading.formatted == "4660"
  end

  test "keeps bit reads as-is for coil/discrete input values" do
    register = %{
      type: :coil,
      data_type: :bool,
      scale: 0,
      swap_words: false,
      swap_bytes: false
    }

    reading = RegisterReading.from_modbus([1], register)

    assert reading.bytes == [1]
    assert reading.value == true
    assert reading.formatted == "true"
  end

  test "keeps bytes as read while swap_words and swap_bytes affect interpreted float value" do
    register = %{
      type: :input_register,
      data_type: :float32,
      scale: 0,
      swap_words: true,
      swap_bytes: true
    }

    reading = RegisterReading.from_modbus([0x0000, 0x803F], register)

    assert reading.bytes == [0x00, 0x00, 0x80, 0x3F]
    assert reading.value == 1.0
    assert reading.formatted == "1.0"
  end

  test "swap_bytes changes interpreted value but not raw byte capture" do
    base_register = %{
      type: :holding_register,
      data_type: :uint32,
      scale: 0,
      swap_words: false,
      swap_bytes: false
    }

    swapped_register = %{base_register | swap_bytes: true}

    base_reading = RegisterReading.from_modbus([0x1234, 0x5678], base_register)
    swapped_reading = RegisterReading.from_modbus([0x1234, 0x5678], swapped_register)

    assert base_reading.bytes == [0x12, 0x34, 0x56, 0x78]
    assert swapped_reading.bytes == [0x12, 0x34, 0x56, 0x78]

    assert base_reading.value == 0x12345678
    assert swapped_reading.value == 0x34127856
    assert swapped_reading.formatted == Integer.to_string(0x34127856)
  end
end
