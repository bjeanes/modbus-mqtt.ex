defmodule ModbusMqtt.Mqtt.HomeAssistantTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Mqtt.HomeAssistant

  defmodule FakeDevices do
    def list_active_devices_with_fields do
      [
        %{
          id: 7,
          name: "Inverter",
          base_topic: "inverter",
          transport_config: %{"host" => "10.10.20.216"},
          fields: [
            %{
              id: 11,
              name: "temperature",
              type: :input_register,
              data_type: :int16,
              value_semantics: :raw,
              bit_mask: nil,
              unit: "°C"
            },
            %{
              id: 12,
              name: "enabled",
              type: :coil,
              data_type: :bool,
              value_semantics: :raw,
              bit_mask: nil,
              unit: nil
            },
            %{
              id: 13,
              name: "mode",
              type: :holding_register,
              data_type: :uint16,
              value_semantics: :enum,
              enum_map: %{"0x01" => "auto", "0x02" => "manual"},
              bit_mask: nil,
              unit: nil
            },
            %{
              id: 14,
              name: "power_limit",
              type: :holding_register,
              data_type: :uint16,
              value_semantics: :raw,
              bit_mask: nil,
              unit: "W"
            }
          ]
        }
      ]
    end
  end

  test "publishes discovery for active fields with non-retained messages" do
    test_pid = self()
    server = String.to_atom("ha_server_#{System.unique_integer([:positive])}")

    start_supervised!(
      {HomeAssistant,
       name: server,
       devices_mod: FakeDevices,
       publish_fun: fn topic, payload, opts ->
         send(test_pid, {:published, topic, payload, opts})
         :ok
       end}
    )

    HomeAssistant.mqtt_connection_changed(server, :up)

    assert_receive {:published, "homeassistant/sensor/modbus_mqtt_inverter_temperature/config",
                    payload_11, []}

    assert_receive {:published, "homeassistant/switch/modbus_mqtt_inverter_enabled/config",
                    payload_12, []}

    assert_receive {:published, "homeassistant/select/modbus_mqtt_inverter_mode/config",
                    payload_13, []}

    assert_receive {:published, "homeassistant/number/modbus_mqtt_inverter_power_limit/config",
                    payload_14, []}

    config_11 = Jason.decode!(payload_11)
    config_12 = Jason.decode!(payload_12)
    config_13 = Jason.decode!(payload_13)
    config_14 = Jason.decode!(payload_14)

    assert config_11["state_topic"] == "modbus_mqtt/inverter/temperature/detail"
    assert config_11["json_attributes_topic"] == "modbus_mqtt/inverter/temperature/detail"
    assert config_11["unique_id"] == "modbus_mqtt_inverter_temperature"
    assert config_11["value_template"] == "{{ value_json.value }}"
    assert config_11["unit_of_measurement"] == "°C"

    assert config_11["availability"] == [
             %{"topic" => "modbus_mqtt/status"},
             %{"topic" => "modbus_mqtt/devices/inverter/status"}
           ]

    assert config_11["device"]["identifiers"] == ["modbus-mqtt-device-7"]
    assert config_11["device"]["connections"] == [["ip", "10.10.20.216"]]

    assert config_12["command_topic"] == "modbus_mqtt/inverter/enabled/set"
    assert config_12["value_template"] == "{{ 'ON' if value_json.value else 'OFF' }}"

    assert config_13["command_topic"] == "modbus_mqtt/inverter/mode/set"
    assert Enum.sort(config_13["options"]) == ["auto", "manual"]

    assert config_14["command_topic"] == "modbus_mqtt/inverter/power_limit/set"
    assert config_14["mode"] == "box"
  end

  test "re-publishes discovery when home assistant comes online" do
    test_pid = self()
    server = String.to_atom("ha_online_server_#{System.unique_integer([:positive])}")

    start_supervised!(
      {HomeAssistant,
       name: server,
       devices_mod: FakeDevices,
       publish_fun: fn topic, payload, opts ->
         send(test_pid, {:published, topic, payload, opts})
         :ok
       end}
    )

    HomeAssistant.mqtt_connection_changed(server, :up)

    for _ <- 1..4 do
      assert_receive {:published, _, _, []}
    end

    HomeAssistant.home_assistant_online(server)

    for _ <- 1..4 do
      assert_receive {:published, _, _, []}
    end
  end
end
