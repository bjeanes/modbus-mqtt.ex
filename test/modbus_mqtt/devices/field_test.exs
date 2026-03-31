defmodule ModbusMqtt.Devices.FieldTest do
  use ModbusMqtt.DataCase, async: true

  alias ModbusMqtt.Devices.Field

  test "accepts enum map keys in decimal, hex, and binary notation" do
    changeset =
      Field.changeset(
        %Field{},
        valid_attrs(%{"100" => "normal", "0xAA" => "alarm", "0b11" => "eco"})
      )

    assert changeset.valid?
  end

  test "rejects invalid enum map keys" do
    changeset = Field.changeset(%Field{}, valid_attrs(%{"0xZZ" => "bad"}))

    refute changeset.valid?

    assert Enum.any?(errors_on(changeset).enum_map, fn message ->
             String.contains?(message, "invalid key")
           end)
  end

  test "rejects duplicate numeric enum key mappings" do
    changeset =
      Field.changeset(%Field{}, valid_attrs(%{"170" => "normal", "0xAA" => "alarm"}))

    refute changeset.valid?

    assert Enum.any?(errors_on(changeset).enum_map, fn message ->
             String.contains?(message, "duplicate numeric key mappings")
           end)
  end

  test "rejects enum semantics for non-uint16 data types" do
    attrs =
      %{"1" => "normal"}
      |> valid_attrs()
      |> Map.put(:data_type, :uint32)

    changeset = Field.changeset(%Field{}, attrs)

    refute changeset.valid?
    assert "must be uint16 when value_semantics is enum" in errors_on(changeset).data_type
  end

  test "rejects non-zero scale when value semantics are enum" do
    attrs =
      %{"1" => "normal"}
      |> valid_attrs()
      |> Map.put(:scale, 1)

    changeset = Field.changeset(%Field{}, attrs)

    refute changeset.valid?
    assert "must be equal to 0" in errors_on(changeset).scale
  end

  test "rejects empty enum map" do
    changeset = Field.changeset(%Field{}, valid_attrs(%{}))

    refute changeset.valid?
    assert "must contain at least one entry" in errors_on(changeset).enum_map
  end

  defp valid_attrs(enum_map) do
    %{
      name: "mode",
      type: :input_register,
      data_type: :uint16,
      address: 13030,
      address_offset: 0,
      poll_interval_ms: 1000,
      writable: false,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :enum,
      enum_map: enum_map,
      device_id: 1
    }
  end
end
