defmodule ModbusMqtt.Devices.FieldTest do
  use ModbusMqtt.DataCase, async: true

  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Repo

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

  describe "measurement units" do
    test "exposes default unit presets" do
      presets = Field.unit_presets()

      assert "°C" in presets
      assert "°F" in presets
      assert "%" in presets
    end

    test "accepts unit for numeric raw fields" do
      attrs = bitmap_attrs(%{name: "temperature", data_type: :int16, unit: " °C "})

      changeset = Field.changeset(%Field{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :unit) == "°C"
    end

    test "rejects unit when value semantics are enum" do
      attrs = valid_attrs(%{"1" => "normal"}) |> Map.put(:unit, "%")

      changeset = Field.changeset(%Field{}, attrs)

      refute changeset.valid?
      assert "can only be set for numeric raw fields" in errors_on(changeset).unit
    end

    test "rejects unit for string fields" do
      attrs =
        bitmap_attrs(%{
          data_type: :string,
          length: 2,
          name: "label",
          value_semantics: :raw,
          unit: "°C"
        })

      changeset = Field.changeset(%Field{}, attrs)

      refute changeset.valid?
      assert "can only be set for numeric raw fields" in errors_on(changeset).unit
    end
  end

  test "determines writability from register type" do
    assert Field.writable?(%{type: :coil})
    assert Field.writable?(%{type: :holding_register})
    refute Field.writable?(%{type: :input_register})
    refute Field.writable?(%{type: :discrete_input})
  end

  test "detects boolean-like enum mappings" do
    field = %{
      value_semantics: :enum,
      enum_map: %{"0x00" => true, "0x55" => false}
    }

    assert Field.enum_boolean?(field)
    assert Field.enum_boolean_codes(field) == {:ok, %{true: 0, false: 0x55}}
  end

  test "does not detect non-boolean enum mappings as boolean-like" do
    field = %{
      value_semantics: :enum,
      enum_map: %{"1" => "auto", "2" => "manual"}
    }

    refute Field.enum_boolean?(field)
    assert Field.enum_boolean_codes(field) == :error
  end

  test "does not detect enum boolean when values are boolean-like strings" do
    field = %{
      value_semantics: :enum,
      enum_map: %{"0x00" => "true", "0x55" => "false"}
    }

    refute Field.enum_boolean?(field)
    assert Field.enum_boolean_codes(field) == :error
  end

  test "enforces field name uniqueness per device" do
    device =
      Repo.insert!(%Device{
        name: "Test Device",
        protocol: :tcp,
        base_topic: "test-device",
        active: true,
        unit: 1,
        transport_config: %{}
      })

    attrs = bitmap_attrs(%{name: "power"})

    assert {:ok, _field} =
             %Field{}
             |> Field.changeset(attrs)
             |> Ecto.Changeset.put_change(:device_id, device.id)
             |> Repo.insert()

    assert {:error, changeset} =
             %Field{}
             |> Field.changeset(Map.put(attrs, :address, 13001))
             |> Ecto.Changeset.put_change(:device_id, device.id)
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).name
  end

  describe "bitmap fields" do
    test "accepts valid bitmap field" do
      changeset = Field.changeset(%Field{}, bitmap_attrs(%{bit_mask: 0x0001}))
      assert changeset.valid?
    end

    test "rejects non-integer data type with bit_mask" do
      changeset = Field.changeset(%Field{}, bitmap_attrs(%{bit_mask: 0x0001, data_type: :string}))
      refute changeset.valid?
      assert "must be an integer type when bit_mask is set" in errors_on(changeset).data_type
    end

    test "rejects non-zero scale with bit_mask" do
      changeset = Field.changeset(%Field{}, bitmap_attrs(%{bit_mask: 0x0001, scale: -1}))
      refute changeset.valid?
      assert "must be 0 when bit_mask is set" in errors_on(changeset).scale
    end

    test "rejects bit_mask of zero" do
      changeset = Field.changeset(%Field{}, bitmap_attrs(%{bit_mask: 0}))
      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).bit_mask
    end

    test "rejects coil type with bit_mask" do
      changeset = Field.changeset(%Field{}, bitmap_attrs(%{bit_mask: 0x0001, type: :coil}))
      refute changeset.valid?

      assert "must be input_register or holding_register when bit_mask is set" in errors_on(
               changeset
             ).type
    end
  end

  defp bitmap_attrs(overrides) do
    %{
      name: "state_flag",
      type: :input_register,
      data_type: :uint16,
      address: 13000,
      address_offset: 0,
      poll_interval_ms: 5000,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw,
      enum_map: %{}
    }
    |> Map.merge(overrides)
  end

  defp valid_attrs(enum_map) do
    %{
      name: "mode",
      type: :input_register,
      data_type: :uint16,
      address: 13030,
      address_offset: 0,
      poll_interval_ms: 1000,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :enum,
      enum_map: enum_map
    }
  end
end
