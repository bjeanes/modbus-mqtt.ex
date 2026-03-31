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
end
