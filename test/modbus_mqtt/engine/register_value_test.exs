defmodule ModbusMqtt.Engine.RegisterValueTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias ModbusMqtt.Engine.RegisterValue

  test "decodes signed 16-bit values" do
    register = %{data_type: :int16, scale: 0, swap_words: false, swap_bytes: false}

    assert RegisterValue.decode([65_535], register) == -1
  end

  test "decodes 32-bit floats with byte and word swapping" do
    register = %{data_type: :float32, scale: 0, swap_words: true, swap_bytes: true}

    assert RegisterValue.decode([0x0000, 0x803F], register) == 1.0
  end

  test "scales numeric values with Decimal" do
    register = %{data_type: :uint16, scale: -1, swap_words: false, swap_bytes: false}

    value = RegisterValue.decode([123], register)

    assert match?(%Decimal{}, value)
    assert D.equal?(value, D.new("12.3"))
  end

  test "decodes boolean coil values" do
    register = %{data_type: :bool, scale: 0, swap_words: false, swap_bytes: false}

    assert RegisterValue.decode([1], register)
    refute RegisterValue.decode([0], register)
  end

  describe "string registers" do
    test "decodes ASCII string from words" do
      # "AB" -> 0x4142, "CD" -> 0x4344
      register = %{data_type: :string, length: 4, scale: 0, swap_words: false, swap_bytes: false}
      assert RegisterValue.decode([0x4142, 0x4344], register) == "ABCD"
    end

    test "trims trailing null bytes from string" do
      # "Hi" with 2 null padding bytes -> 0x4869, 0x0000
      register = %{data_type: :string, length: 4, scale: 0, swap_words: false, swap_bytes: false}
      assert RegisterValue.decode([0x4869, 0x0000], register) == "Hi"
    end

    test "word_count for string with even length" do
      register = %{data_type: :string, length: 10}
      assert RegisterValue.word_count(register) == 5
    end

    test "word_count for string with odd length" do
      register = %{data_type: :string, length: 9}
      assert RegisterValue.word_count(register) == 5
    end

    test "word_count for non-string register struct" do
      assert RegisterValue.word_count(%{data_type: :uint32, length: 2}) == 2
      assert RegisterValue.word_count(%{data_type: :uint16, length: 1}) == 1
      assert RegisterValue.word_count(%{data_type: :float32, length: 2}) == 2
    end
  end
end
