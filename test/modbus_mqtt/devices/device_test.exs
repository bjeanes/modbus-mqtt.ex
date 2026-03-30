defmodule ModbusMqtt.Devices.DeviceTest do
  use ModbusMqtt.DataCase, async: false

  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Topic
  alias ModbusMqtt.Repo

  test "normalizes blank topic aliases to nil" do
    changeset =
      Device.changeset(%Device{}, %{
        name: "Inverter",
        protocol: :tcp,
        base_topic: "   ",
        active: true,
        unit: 1,
        transport_config: %{}
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :base_topic) == nil
  end

  test "rejects multi-segment or wildcard topic aliases" do
    changeset =
      Device.changeset(%Device{}, %{
        name: "Inverter",
        protocol: :tcp,
        base_topic: "site/inverter",
        active: true,
        unit: 1,
        transport_config: %{}
      })

    refute changeset.valid?

    assert "must be a single MQTT topic segment without wildcards or slashes" in errors_on(
             changeset
           ).base_topic
  end

  test "enforces unique topic aliases" do
    attrs = %{
      name: "Inverter",
      protocol: :tcp,
      base_topic: "sungrow",
      active: true,
      unit: 1,
      transport_config: %{}
    }

    assert {:ok, _device} = %Device{} |> Device.changeset(attrs) |> Repo.insert()

    assert {:error, changeset} =
             %Device{}
             |> Device.changeset(Map.put(attrs, :name, "Inverter 2"))
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).base_topic
  end

  test "falls back to the device id when no topic alias is configured" do
    assert Topic.key(%{id: 42, base_topic: nil}) == "42"
    assert Topic.key(%{id: 42, base_topic: "alias"}) == "alias"
  end
end
