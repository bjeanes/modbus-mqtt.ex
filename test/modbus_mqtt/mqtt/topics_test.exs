defmodule ModbusMqtt.Mqtt.TopicsTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Mqtt.Topics

  describe "parse_set_topic/1" do
    test "parses a valid /set topic into device and field segments" do
      assert Topics.parse_set_topic("modbus_mqtt/my-device/my-field/set") ==
               {:ok, {"my-device", "my-field"}}
    end

    test "parses topic levels list from Tortoise handler" do
      assert Topics.parse_set_topic(["modbus_mqtt", "my-device", "my-field", "set"]) ==
               {:ok, {"my-device", "my-field"}}
    end

    test "returns error for a non-/set topic" do
      assert Topics.parse_set_topic("modbus_mqtt/my-device/my-field") ==
               {:error, :not_set_topic}
    end

    test "returns error for topic with wrong base" do
      assert Topics.parse_set_topic("other_base/my-device/my-field/set") ==
               {:error, :not_set_topic}
    end

    test "returns error for /set topic with missing field segment" do
      assert Topics.parse_set_topic("modbus_mqtt/my-device/set") ==
               {:error, :not_set_topic}
    end

    test "returns error for topic with extra segments after /set" do
      assert Topics.parse_set_topic("modbus_mqtt/my-device/my-field/set/extra") ==
               {:error, :not_set_topic}
    end

    test "accepts charlists as well as binaries" do
      assert Topics.parse_set_topic(~c"modbus_mqtt/my-device/my-field/set") ==
               {:ok, {"my-device", "my-field"}}
    end

    test "returns error for invalid list topic levels" do
      assert Topics.parse_set_topic(["modbus_mqtt", :bad, "my-field", "set"]) ==
               {:error, :not_set_topic}
    end
  end
end
