defmodule ModbusMqtt.Mqtt.TopicsTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Mqtt.Topics

  defp device(attrs) do
    Map.merge(%{id: 42, base_topic: nil}, attrs)
  end

  defp field(attrs \\ %{}) do
    Map.merge(%{name: "power"}, attrs)
  end

  describe "base_topic/0" do
    test "returns configured base topic" do
      assert Topics.base_topic() == "modbus_mqtt"
    end
  end

  describe "normalize_base_segments/1" do
    test "splits binary base topics" do
      assert Topics.normalize_base_segments("a/b/c") == ["a", "b", "c"]
    end

    test "drops empty segments from list input" do
      assert Topics.normalize_base_segments(["a", "", "b"]) == ["a", "b"]
    end

    test "falls back to configured base when list is invalid" do
      assert Topics.normalize_base_segments(["a", :bad]) == ["modbus_mqtt"]
    end
  end

  describe "bridge_status_topic/0" do
    test "builds bridge status topic" do
      assert Topics.bridge_status_topic() == "modbus_mqtt/status"
    end
  end

  describe "home_assistant_discovery_prefix/0" do
    test "uses default discovery prefix" do
      assert Topics.home_assistant_discovery_prefix() == "homeassistant"
    end
  end

  describe "home_assistant_status_topic/0" do
    test "builds home assistant status topic" do
      assert Topics.home_assistant_status_topic() == "homeassistant/status"
    end
  end

  describe "home_assistant_discovery_topic/2" do
    test "builds discovery config topic" do
      assert Topics.home_assistant_discovery_topic("sensor", "field_12") ==
               "homeassistant/sensor/field_12/config"
    end
  end

  describe "device_value_topic/2" do
    test "uses device id when device base_topic is missing" do
      assert Topics.device_value_topic(device(%{id: 7}), field(%{name: "temperature"})) ==
               "modbus_mqtt/7/temperature"
    end

    test "uses device base_topic when present" do
      assert Topics.device_value_topic(device(%{id: 7, base_topic: "inverter"}), field()) ==
               "modbus_mqtt/inverter/power"
    end
  end

  describe "device_value_detail_topic/2" do
    test "appends detail suffix" do
      assert Topics.device_value_detail_topic(device(%{id: 7}), field(%{name: "temperature"})) ==
               "modbus_mqtt/7/temperature/detail"
    end
  end

  describe "device_value_set_topic/2" do
    test "appends set suffix" do
      assert Topics.device_value_set_topic(device(%{id: 7}), field(%{name: "setpoint"})) ==
               "modbus_mqtt/7/setpoint/set"
    end
  end

  describe "device_value_set_topic_filter/0" do
    test "builds wildcard set topic filter" do
      assert Topics.device_value_set_topic_filter() == "modbus_mqtt/+/+/set"
    end
  end

  describe "device_status_topic/1" do
    test "builds device status topic" do
      assert Topics.device_status_topic(device(%{id: 7})) == "modbus_mqtt/devices/7/status"
    end
  end

  describe "device_last_error_topic/1" do
    test "builds device last error topic" do
      assert Topics.device_last_error_topic(device(%{id: 7})) ==
               "modbus_mqtt/devices/7/last_error"
    end
  end

  describe "join/1" do
    test "joins non-empty segments" do
      assert Topics.join(["modbus_mqtt", "device", "field"]) == "modbus_mqtt/device/field"
    end

    test "filters nil and empty string segments" do
      assert Topics.join(["modbus_mqtt", nil, "", "device", nil, "field", ""]) ==
               "modbus_mqtt/device/field"
    end

    test "returns empty string for empty input" do
      assert Topics.join([]) == ""
    end
  end

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

    test "returns error for integer list that is not a valid topic" do
      assert Topics.parse_set_topic([1, 2, 3]) == {:error, :not_set_topic}
    end

    test "returns error for invalid list topic levels" do
      assert Topics.parse_set_topic(["modbus_mqtt", :bad, "my-field", "set"]) ==
               {:error, :not_set_topic}
    end
  end

  describe "parse_set_topic/2" do
    test "parses topic using injected base segments" do
      assert Topics.parse_set_topic("custom/dev-1/mode/set", base_segments: ["custom"]) ==
               {:ok, {"dev-1", "mode"}}
    end

    test "returns error when injected base segments do not match" do
      assert Topics.parse_set_topic("modbus_mqtt/dev-1/mode/set", base_segments: ["custom"]) ==
               {:error, :not_set_topic}
    end
  end
end
