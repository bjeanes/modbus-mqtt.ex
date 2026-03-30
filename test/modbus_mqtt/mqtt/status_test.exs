defmodule ModbusMqtt.Mqtt.StatusTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Mqtt.Status

  test "publishes the retained bridge state and buffered device snapshot when mqtt comes up" do
    test_pid = self()
    server = String.to_atom("status_server_#{System.unique_integer([:positive])}")

    start_supervised!(
      {Status,
       name: server,
       publish_fun: fn topic, payload, opts ->
         send(test_pid, {:published, topic, payload, opts})
         :ok
       end}
    )

    device = %{id: 9, name: "Status Device", base_topic: nil}

    Status.device_connecting(server, device)
    Status.device_error(server, device, "timeout")

    refute_receive {:published, _, _, _}

    Status.mqtt_connection_changed(server, :up)

    assert_receive {:published, "modbus_mqtt/status", "online", [retain: true]}
    assert_receive {:published, "modbus_mqtt/devices/9/status", "connecting", [retain: true]}
    assert_receive {:published, "modbus_mqtt/devices/9/last_error", "timeout", [retain: true]}

    Status.clear_device_error(server, device)
    assert_receive {:published, "modbus_mqtt/devices/9/last_error", nil, [retain: true]}
  end
end
