defmodule ModbusMqtt.Engine.FieldCodecTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias ModbusMqtt.Engine.FieldCodec

  test "decodes signed 16-bit values" do
    field = %{data_type: :int16, scale: 0, swap_words: false, swap_bytes: false}

    assert FieldCodec.decode([65_535], field) == -1
  end

  test "decodes 32-bit floats with byte and word swapping" do
    field = %{data_type: :float32, scale: 0, swap_words: true, swap_bytes: true}

    assert FieldCodec.decode([0x0000, 0x803F], field) == 1.0
  end

  test "scales numeric values with Decimal" do
    field = %{data_type: :uint16, scale: -1, swap_words: false, swap_bytes: false}

    value = FieldCodec.decode([123], field)

    assert match?(%Decimal{}, value)
    assert D.equal?(value, D.new("12.3"))
  end

  test "decodes boolean coil values" do
    field = %{data_type: :bool, scale: 0, swap_words: false, swap_bytes: false}

    assert FieldCodec.decode([1], field)
    refute FieldCodec.decode([0], field)
  end

  describe "string fields" do
    test "decodes ASCII string from words" do
      field = %{data_type: :string, length: 4, scale: 0, swap_words: false, swap_bytes: false}
      assert FieldCodec.decode([0x4142, 0x4344], field) == "ABCD"
    end

    test "trims trailing null bytes from string" do
      field = %{data_type: :string, length: 4, scale: 0, swap_words: false, swap_bytes: false}
      assert FieldCodec.decode([0x4869, 0x0000], field) == "Hi"
    end

    test "word_count for string with even length" do
      field = %{data_type: :string, length: 10}
      assert FieldCodec.word_count(field) == 5
    end

    test "word_count for string with odd length" do
      field = %{data_type: :string, length: 9}
      assert FieldCodec.word_count(field) == 5
    end

    test "word_count for non-string field struct" do
      assert FieldCodec.word_count(%{data_type: :uint32, length: 2}) == 2
      assert FieldCodec.word_count(%{data_type: :uint16, length: 1}) == 1
      assert FieldCodec.word_count(%{data_type: :float32, length: 2}) == 2
    end
  end
end
