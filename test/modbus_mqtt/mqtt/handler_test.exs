defmodule ModbusMqtt.Mqtt.HandlerTest do
  use ExUnit.Case, async: true

  alias ModbusMqtt.Mqtt.Handler

  defmodule FakeDevices do
    def find_active_field_by_topic("dev-1", "mode") do
      {%{id: 1, unit: 1, name: "Device 1"},
       %{name: "mode", type: :holding_register, value_semantics: :raw}}
    end

    def find_active_field_by_topic(_, _), do: nil
  end

  defmodule FakeWriter do
    def write(device, field, value) do
      send(self(), {:write, device, field, value})
      :ok
    end
  end

  test "handles inbound /set payloads and routes decoded value to writer" do
    {:ok, state} = Handler.init(devices: FakeDevices, writer: FakeWriter)

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode/set", "42", state)

    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}
  end

  test "handles inbound /set payloads from Tortoise topic levels" do
    {:ok, state} = Handler.init(devices: FakeDevices, writer: FakeWriter)

    assert {:ok, ^state} =
             Handler.handle_message(["modbus_mqtt", "dev-1", "mode", "set"], "42", state)

    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}
  end

  test "ignores non-/set topics" do
    {:ok, state} = Handler.init(devices: FakeDevices, writer: FakeWriter)

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode", "42", state)
    refute_receive {:write, _, _, _}
  end

  test "uses configured base segments from init when parsing topics" do
    {:ok, state} = Handler.init(devices: FakeDevices, writer: FakeWriter, base_segments: "custom")

    assert {:ok, ^state} = Handler.handle_message("custom/dev-1/mode/set", "42", state)
    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode/set", "42", state)
    refute_receive {:write, _, _, _}
  end
end
