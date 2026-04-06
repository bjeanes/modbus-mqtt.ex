defmodule ModbusMqtt.Devices.DeviceTest do
  use ModbusMqtt.DataCase, async: false

  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Topic

  test "accepts metadata-only device attributes" do
    changeset =
      Device.changeset(%Device{}, %{
        name: "Inverter",
        manufacturer: "Sungrow",
        model_number: "SH10RT"
      })

    assert changeset.valid?
  end

  test "requires a name" do
    changeset =
      Device.changeset(%Device{}, %{
        manufacturer: "Sungrow"
      })

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).name
  end

  test "topic helper falls back to id when no topic alias is configured" do
    assert Topic.key(%{id: 42, base_topic: nil}) == "42"
    assert Topic.key(%{id: 42, base_topic: "alias"}) == "alias"
  end
end
