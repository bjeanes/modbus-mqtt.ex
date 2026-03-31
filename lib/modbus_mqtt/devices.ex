defmodule ModbusMqtt.Devices do
  @moduledoc """
  Context module for device and field management.
  Centralizes queries, changesets, and validation for devices and fields.
  """
  import Ecto.Query
  require Logger

  alias ModbusMqtt.Repo
  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Field

  @doc "Lists all active devices with their fields preloaded"
  def list_active_devices_with_fields do
    query =
      from d in Device,
        where: d.active == true,
        preload: [:fields]

    Repo.all(query)
  end

  @doc "Gets a single device by ID with fields preloaded"
  def get_device!(id) do
    Repo.get!(Device, id)
    |> Repo.preload(:fields)
  end

  @doc "Gets a device by ID without raising if not found"
  def get_device(id) do
    case Repo.get(Device, id) do
      nil -> nil
      device -> Repo.preload(device, :fields)
    end
  end

  @doc "Creates a new device"
  def create_device(attrs \\ %{}) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
    |> maybe_reconcile_engine()
  end

  @doc "Updates a device"
  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
    |> maybe_reconcile_engine()
  end

  @doc "Deletes a device"
  def delete_device(%Device{} = device) do
    device
    |> Repo.delete()
    |> maybe_reconcile_engine()
  end

  @doc "Returns a device changeset for use in forms"
  def change_device(%Device{} = device, attrs \\ %{}) do
    Device.changeset(device, attrs)
  end

  @doc "Creates a new field for a device"
  def create_field(device_id, attrs \\ %{}) do
    %Field{}
    |> Field.changeset(attrs)
    |> Ecto.Changeset.put_change(:device_id, device_id)
    |> Repo.insert()
    |> maybe_reconcile_engine()
  end

  @doc "Updates a field"
  def update_field(%Field{} = field, attrs) do
    field
    |> Field.changeset(attrs)
    |> Repo.update()
    |> maybe_reconcile_engine()
  end

  @doc "Deletes a field"
  def delete_field(%Field{} = field) do
    field
    |> Repo.delete()
    |> maybe_reconcile_engine()
  end

  @doc "Returns a field changeset for use in forms"
  def change_field(%Field{} = field, attrs \\ %{}) do
    Field.changeset(field, attrs)
  end

  @doc "Lists fields for a device"
  def list_fields_for_device(device_id) do
    query =
      from f in Field,
        where: f.device_id == ^device_id

    Repo.all(query)
  end

  @doc "Gets a single field by ID"
  def get_field!(id) do
    Repo.get!(Field, id)
  end

  @doc "Gets a field by ID without raising if not found"
  def get_field(id) do
    Repo.get(Field, id)
  end

  defp maybe_reconcile_engine({:ok, _record} = result) do
    ModbusMqtt.Engine.Reconciler.reconcile_now()
    result
  end

  defp maybe_reconcile_engine(result), do: result
end
