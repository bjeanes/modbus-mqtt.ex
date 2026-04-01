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

  describe "bitmap fields" do
    test "extracts single bit as boolean true" do
      field = %{
        data_type: :uint16,
        scale: 0,
        swap_words: false,
        swap_bytes: false,
        bit_mask: 0x0004
      }

      assert FieldCodec.decode([0x000F], field) == true
    end

    test "extracts single bit as boolean false" do
      field = %{
        data_type: :uint16,
        scale: 0,
        swap_words: false,
        swap_bytes: false,
        bit_mask: 0x0004
      }

      assert FieldCodec.decode([0x0003], field) == false
    end

    test "extracts high bit from uint16" do
      field = %{
        data_type: :uint16,
        scale: 0,
        swap_words: false,
        swap_bytes: false,
        bit_mask: 0x8000
      }

      assert FieldCodec.decode([0x8001], field) == true
      assert FieldCodec.decode([0x7FFF], field) == false
    end

    test "works with multi-bit mask" do
      field = %{
        data_type: :uint16,
        scale: 0,
        swap_words: false,
        swap_bytes: false,
        bit_mask: 0x0003
      }

      # Bit 0 set → mask matches
      assert FieldCodec.decode([0x0001], field) == true
      # No bits from mask set
      assert FieldCodec.decode([0x0004], field) == false
    end

    test "without bit_mask, returns integer as normal" do
      field = %{data_type: :uint16, scale: 0, swap_words: false, swap_bytes: false}

      assert FieldCodec.decode([0x000F], field) == 15
    end
  end

  describe "encode_write/2" do
    test "encodes coil booleans" do
      assert FieldCodec.encode_write(true, %{type: :coil}) == {:ok, [1]}
      assert FieldCodec.encode_write("false", %{type: :coil}) == {:ok, [0]}
    end

    test "inverts scale for integer register writes" do
      field = %{type: :holding_register, data_type: :uint16, scale: -1}

      assert FieldCodec.encode_write(D.new("12.3"), field) == {:ok, [123]}
    end

    test "rejects out-of-range values" do
      field = %{type: :holding_register, data_type: :uint16, scale: 0}

      assert FieldCodec.encode_write(70_000, field) ==
               {:error, {:out_of_range, 70_000, 0, 65_535}}
    end

    test "encodes uint32 with configured word and byte swap" do
      field = %{
        type: :holding_register,
        data_type: :uint32,
        scale: 0,
        swap_words: true,
        swap_bytes: true
      }

      assert FieldCodec.encode_write(0x11223344, field) == {:ok, [0x4433, 0x2211]}
    end
  end
end
