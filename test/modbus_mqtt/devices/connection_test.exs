defmodule ModbusMqtt.Devices.ConnectionTest do
  use ModbusMqtt.DataCase, async: false

  alias ModbusMqtt.Devices.Connection
  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Repo

  defp device! do
    Repo.insert!(%Device{name: "Inverter"})
  end

  test "requires base_topic" do
    changeset =
      %Connection{}
      |> Connection.changeset(%{
        protocol: :tcp,
        base_topic: "   ",
        active: true,
        unit: 1,
        transport_config: %{}
      })
      |> Ecto.Changeset.put_change(:device_id, device!().id)

    refute changeset.valid?
    assert "can't be blank" in errors_on(changeset).base_topic
  end

  test "normalizes surrounding whitespace in base_topic" do
    changeset =
      %Connection{}
      |> Connection.changeset(%{
        protocol: :tcp,
        base_topic: "  inverter-1  ",
        active: true,
        unit: 1,
        transport_config: %{}
      })
      |> Ecto.Changeset.put_change(:device_id, device!().id)

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :base_topic) == "inverter-1"
  end

  test "rejects multi-segment or wildcard topic aliases" do
    changeset =
      %Connection{}
      |> Connection.changeset(%{
        protocol: :tcp,
        base_topic: "site/inverter",
        active: true,
        unit: 1,
        transport_config: %{}
      })
      |> Ecto.Changeset.put_change(:device_id, device!().id)

    refute changeset.valid?

    assert "must be a single MQTT topic segment without wildcards or slashes" in errors_on(
             changeset
           ).base_topic
  end

  test "enforces unique topic aliases across connections" do
    device = device!()

    attrs = %{
      protocol: :tcp,
      base_topic: "sungrow",
      active: true,
      unit: 1,
      transport_config: %{}
    }

    assert {:ok, _connection} =
             %Connection{}
             |> Connection.changeset(attrs)
             |> Ecto.Changeset.put_change(:device_id, device.id)
             |> Repo.insert()

    assert {:error, changeset} =
             %Connection{}
             |> Connection.changeset(attrs)
             |> Ecto.Changeset.put_change(:device_id, device.id)
             |> Repo.insert()

    assert "has already been taken" in errors_on(changeset).base_topic
  end
end
