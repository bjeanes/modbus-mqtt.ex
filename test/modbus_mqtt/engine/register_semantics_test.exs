defmodule ModbusMqtt.Engine.RegisterSemanticsTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias ModbusMqtt.Engine.RegisterSemantics

  test "maps enum decoded value to semantic label" do
    register = %{value_semantics: :enum, enum_map: %{"1" => "standby", "0xAA" => "maintenance"}}

    assert RegisterSemantics.to_value(170, register) == "maintenance"
  end

  test "falls back to decoded string when enum key is unknown" do
    register = %{value_semantics: :enum, enum_map: %{"1" => "standby"}}

    assert RegisterSemantics.to_value(2, register) == "2"
  end

  test "reverse maps semantic labels and parses numeric literal input" do
    register = %{value_semantics: :enum, enum_map: %{"1" => "standby", "0xAA" => "maintenance"}}

    assert RegisterSemantics.from_value("maintenance", register) == {:ok, 170}
    assert RegisterSemantics.from_value("0b11", register) == {:ok, 3}
  end

  test "formats Decimal and binary values" do
    assert RegisterSemantics.format(D.new("12.3")) == "12.3"
    assert RegisterSemantics.format("maintenance") == "maintenance"
  end
end
