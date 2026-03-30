defmodule ModbusMqtt.Client.HexModbusTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Client.HexModbus

  test "returns a descriptive error for invalid tcp hosts" do
    assert {:error, {:invalid_host, "not-an-ip", _reason}} =
             HexModbus.open(%{"protocol" => "tcp", "host" => "not-an-ip"})
  end
end
