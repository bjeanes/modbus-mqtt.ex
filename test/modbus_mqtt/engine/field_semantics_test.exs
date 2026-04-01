defmodule ModbusMqtt.Engine.FieldSemanticsTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias ModbusMqtt.Engine.FieldSemantics

  test "maps enum decoded value to semantic label" do
    field = %{value_semantics: :enum, enum_map: %{"1" => "standby", "0xAA" => "maintenance"}}

    assert FieldSemantics.to_value(170, field) == "maintenance"
  end

  test "falls back to decoded string when enum key is unknown" do
    field = %{value_semantics: :enum, enum_map: %{"1" => "standby"}}

    assert FieldSemantics.to_value(2, field) == "2"
  end

  test "reverse maps semantic labels and parses numeric literal input" do
    field = %{value_semantics: :enum, enum_map: %{"1" => "standby", "0xAA" => "maintenance"}}

    assert FieldSemantics.from_value("maintenance", field) == {:ok, 170}
    assert FieldSemantics.from_value("0b11", field) == {:ok, 3}
  end

  test "formats Decimal and binary values" do
    assert FieldSemantics.format(D.new("12.3")) == "12.3"
    assert FieldSemantics.format("maintenance") == "maintenance"
  end

  test "formats numeric values with unit when field includes unit" do
    field = %{unit: "°C"}

    assert FieldSemantics.format(12345.67, field) == "12345.67 °C"
    assert FieldSemantics.format(D.new("9876.5"), field) == "9876.5 °C"
  end

  test "does not append unit for non-numeric semantic values" do
    field = %{unit: "%"}

    assert FieldSemantics.format("maintenance", field) == "maintenance"
  end

  test "handles nil enum_map gracefully for to_value" do
    field = %{value_semantics: :enum, enum_map: nil}

    assert FieldSemantics.to_value(1, field) == "1"
  end

  test "handles nil enum_map gracefully for from_value" do
    field = %{value_semantics: :enum, enum_map: nil}

    assert FieldSemantics.from_value(1, field) == {:ok, 1}
    assert FieldSemantics.from_value("1", field) == {:ok, 1}
  end
end
