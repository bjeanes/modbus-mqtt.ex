defmodule ModbusMqtt.Engine.HubTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
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

    reading = %{bytes: [0, 10], value: 10, formatted: "10"}
    Hub.put_value(server, device, register, reading)

    assert_receive {:broadcast, 7, "power", 10}
    assert_receive {:published, "modbus_mqtt/7/power", "10", []}
    assert_receive {:published, "modbus_mqtt/7/power/detail", detail_payload, []}
    assert Jason.decode!(detail_payload) == %{"bytes" => [0, 10], "value" => 10}
    assert Hub.get_device_state(table, 7) == %{"power" => 10}

    same_bytes_different_derived = %{bytes: [0, 10], value: 999, formatted: "999"}
    Hub.put_value(server, device, register, same_bytes_different_derived)

    refute_receive {:broadcast, 7, "power", 999}
    refute_receive {:published, "modbus_mqtt/7/power", "999", []}
    refute_receive {:published, "modbus_mqtt/7/power/detail", _, []}
  end

  test "publishes Decimal values as numeric JSON in detail payload" do
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

    device = %{id: 8, name: "Hub Device", base_topic: nil}
    register = %{name: "energy"}

    reading = %{bytes: [0x30, 0x39], value: D.new("123.45"), formatted: "123.45"}
    Hub.put_value(server, device, register, reading)

    assert_receive {:broadcast, 8, "energy", %Decimal{} = value}
    assert D.equal?(value, D.new("123.45"))
    assert_receive {:published, "modbus_mqtt/8/energy", "123.45", []}
    assert_receive {:published, "modbus_mqtt/8/energy/detail", detail_payload, []}
    assert Jason.decode!(detail_payload) == %{"bytes" => [48, 57], "value" => 123.45}
  end
end
