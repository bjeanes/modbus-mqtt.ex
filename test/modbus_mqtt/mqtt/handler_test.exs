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

  defmodule FailingWriter do
    def write(_device, _field, _value), do: {:error, :device_not_running}
  end

  defmodule FakeHomeAssistant do
    def mqtt_connection_changed(status) do
      send(self(), {:ha_mqtt_connection_changed, status})
      :ok
    end

    def home_assistant_online do
      send(self(), :ha_online)
      :ok
    end
  end

  test "handles inbound /set payloads and routes decoded value to writer" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FakeWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode/set", "42", state)

    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}
  end

  test "handles inbound /set payloads from Tortoise topic levels" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FakeWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} =
             Handler.handle_message(["modbus_mqtt", "dev-1", "mode", "set"], "42", state)

    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}
  end

  test "ignores non-/set topics" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FakeWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode", "42", state)
    refute_receive {:write, _, _, _}
  end

  test "uses configured base segments from init when parsing topics" do
    {:ok, state} =
      Handler.init(
        devices: FakeDevices,
        writer: FakeWriter,
        base_segments: "custom",
        home_assistant: FakeHomeAssistant
      )

    assert {:ok, ^state} = Handler.handle_message("custom/dev-1/mode/set", "42", state)
    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode/set", "42", state)
    refute_receive {:write, _, _, _}
  end

  test "accepts list base segments from init" do
    {:ok, state} =
      Handler.init(
        devices: FakeDevices,
        writer: FakeWriter,
        base_segments: ["custom"],
        home_assistant: FakeHomeAssistant
      )

    assert {:ok, ^state} = Handler.handle_message("custom/dev-1/mode/set", "42", state)
    assert_receive {:write, %{name: "Device 1"}, %{name: "mode"}, 42}
  end

  test "returns ok state when writer returns error" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FailingWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} = Handler.handle_message("modbus_mqtt/dev-1/mode/set", "42", state)
    refute_receive {:write, _, _, _}
  end

  test "forwards connection events to home assistant publisher" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FakeWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} = Handler.connection(:up, state)
    assert_receive {:ha_mqtt_connection_changed, :up}
  end

  test "triggers discovery republish when home assistant reports online" do
    {:ok, state} =
      Handler.init(devices: FakeDevices, writer: FakeWriter, home_assistant: FakeHomeAssistant)

    assert {:ok, ^state} = Handler.handle_message("homeassistant/status", "online", state)
    assert_receive :ha_online
  end
end
