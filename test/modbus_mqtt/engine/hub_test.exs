defmodule ModbusMqtt.Engine.HubTest do
  use ExUnit.Case, async: true

  alias Decimal, as: D
  alias ModbusMqtt.Engine.Hub

  test "always refreshes cache and publishes when bytes or value changes" do
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
       broadcast_fun: fn _pubsub, device_id, field_name, value ->
         send(test_pid, {:broadcast, device_id, field_name, value})
         :ok
       end}
    )

    device = %{id: 7, name: "Hub Device", base_topic: nil}
    field = %{name: "power"}

    reading = %{bytes: [0, 10], decoded: 10, value: 10, formatted: "10"}
    Hub.put_value(server, device, field, reading)

    assert_receive {:broadcast, 7, "power", 10}
    assert_receive {:published, "modbus_mqtt/7/power", "10", []}
    assert_receive {:published, "modbus_mqtt/7/power/detail", detail_payload, []}
    assert Jason.decode!(detail_payload) == %{"bytes" => [0, 10], "decoded" => 10, "value" => 10}
    assert Hub.get_device_state(table, 7) == %{"power" => 10}

    assert Hub.get_device_readings(table, 7) == %{
             "power" => %{value: 10, formatted: "10", updated_at: ~U[2026-03-31 12:00:00Z]}
           }

    assert Hub.get_field_reading(table, 7, "power") == %{
             value: 10,
             formatted: "10",
             updated_at: ~U[2026-03-31 12:00:00Z]
           }

    same_bytes_different_derived = %{
      bytes: [0, 10],
      decoded: 10,
      value: "running",
      formatted: "running"
    }

    Hub.put_value(server, device, field, same_bytes_different_derived)

    assert_receive {:broadcast, 7, "power", "running"}
    assert_receive {:published, "modbus_mqtt/7/power", "running", []}
    assert_receive {:published, "modbus_mqtt/7/power/detail", detail_payload_2, []}

    assert Jason.decode!(detail_payload_2) == %{
             "bytes" => [0, 10],
             "decoded" => 10,
             "value" => "running"
           }

    assert Hub.get_field_reading(table, 7, "power") == %{
             value: "running",
             formatted: "running",
             updated_at: ~U[2026-03-31 12:00:00Z]
           }

    Hub.put_value(server, device, field, same_bytes_different_derived)

    refute_receive {:broadcast, 7, "power", "running"}
    refute_receive {:published, "modbus_mqtt/7/power", "running", []}
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
       broadcast_fun: fn _pubsub, device_id, field_name, value ->
         send(test_pid, {:broadcast, device_id, field_name, value})
         :ok
       end}
    )

    device = %{id: 8, name: "Hub Device", base_topic: nil}
    field = %{name: "energy"}

    reading = %{
      bytes: [0x30, 0x39],
      decoded: D.new("123.45"),
      value: D.new("123.45"),
      formatted: "123.45"
    }

    Hub.put_value(server, device, field, reading)

    assert_receive {:broadcast, 8, "energy", %Decimal{} = value}
    assert D.equal?(value, D.new("123.45"))
    assert_receive {:published, "modbus_mqtt/8/energy", "123.45", []}
    assert_receive {:published, "modbus_mqtt/8/energy/detail", detail_payload, []}

    assert Jason.decode!(detail_payload) == %{
             "bytes" => [48, 57],
             "decoded" => 123.45,
             "value" => 123.45
           }
  end

  test "publishes semantic value for enum fields while preserving decoded in detail" do
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
       broadcast_fun: fn _pubsub, device_id, field_name, value ->
         send(test_pid, {:broadcast, device_id, field_name, value})
         :ok
       end}
    )

    device = %{id: 9, name: "Hub Device", base_topic: nil}
    field = %{name: "mode"}
    reading = %{bytes: [0x00, 0xAA], decoded: 170, value: "maintenance", formatted: "maintenance"}

    Hub.put_value(server, device, field, reading)

    assert_receive {:broadcast, 9, "mode", "maintenance"}
    assert_receive {:published, "modbus_mqtt/9/mode", "maintenance", []}
    assert_receive {:published, "modbus_mqtt/9/mode/detail", detail_payload, []}

    assert Jason.decode!(detail_payload) == %{
             "bytes" => [0, 170],
             "decoded" => 170,
             "value" => "maintenance"
           }
  end
end
