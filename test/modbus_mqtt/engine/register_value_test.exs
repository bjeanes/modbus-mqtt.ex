defmodule ModbusMqtt.Engine.RegisterValueTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Engine.RegisterValue

  test "decodes signed 16-bit values" do
    register = %{data_type: :int16, scale: 0, swap_words: false, swap_bytes: false}

    assert RegisterValue.decode([65_535], register) == -1
  end

  test "decodes 32-bit floats with byte and word swapping" do
    register = %{data_type: :float32, scale: 0, swap_words: true, swap_bytes: true}

    assert RegisterValue.decode([0x0000, 0x803F], register) == 1.0
  end

  test "scales numeric values" do
    register = %{data_type: :uint16, scale: -1, swap_words: false, swap_bytes: false}

    assert RegisterValue.decode([123], register) == 12.3
  end

  test "decodes boolean coil values" do
    register = %{data_type: :bool, scale: 0, swap_words: false, swap_bytes: false}

    assert RegisterValue.decode([1], register)
    refute RegisterValue.decode([0], register)
  end
end
