defmodule ModbusMqtt.Engine.HubTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Engine.Hub

  test "publishes and broadcasts only when a value changes" do
    test_pid = self()
    server = String.to_atom("hub_server_#{System.unique_integer([:positive])}")
    table = String.to_atom("hub_table_#{System.unique_integer([:positive])}")

    start_supervised!(
      {Hub,
       name: server,
       table: table,
       now_fun: fn -> ~U[2026-03-31 12:00:00Z] end,
       publish_fun: fn topic, payload, opts ->
         send(test_pid, {:published, topic, payload, opts})
         :ok
       end,
       broadcast_fun: fn _pubsub, device_id, register_name, value ->
         send(test_pid, {:broadcast, device_id, register_name, value})
         :ok
       end}
    )

    device = %{id: 7, name: "Hub Device", base_topic: nil}
    register = %{name: "power"}

    Hub.put_value(server, device, register, 10)

    assert_receive {:broadcast, 7, "power", 10}
    assert_receive {:published, "modbus_mqtt/7/power", 10, []}
    assert Hub.get_device_state(table, 7) == %{"power" => 10}

    Hub.put_value(server, device, register, 10)

    refute_receive {:broadcast, 7, "power", 10}
    refute_receive {:published, "modbus_mqtt/7/power", 10, []}
  end
end
