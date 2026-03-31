defmodule ModbusMqtt.Devices do
  @moduledoc """
  Context module for device and register management.
  Centralizes queries, changesets, and validation for devices and registers.
  """
  import Ecto.Query
  require Logger

  alias ModbusMqtt.Repo
  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Register

  @doc "Lists all active devices with their registers preloaded"
  def list_active_devices_with_registers do
    query =
      from d in Device,
        where: d.active == true,
        preload: [:registers]

    Repo.all(query)
  end

  @doc "Gets a single device by ID with registers preloaded"
  def get_device!(id) do
    Repo.get!(Device, id)
    |> Repo.preload(:registers)
  end

  @doc "Gets a device by ID without raising if not found"
  def get_device(id) do
    case Repo.get(Device, id) do
      nil -> nil
      device -> Repo.preload(device, :registers)
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

  @doc "Creates a new register for a device"
  def create_register(device_id, attrs \\ %{}) do
    %Register{}
    |> Register.changeset(Map.put(attrs, "device_id", device_id))
    |> Repo.insert()
    |> maybe_reconcile_engine()
  end

  @doc "Updates a register"
  def update_register(%Register{} = register, attrs) do
    register
    |> Register.changeset(attrs)
    |> Repo.update()
    |> maybe_reconcile_engine()
  end

  @doc "Deletes a register"
  def delete_register(%Register{} = register) do
    register
    |> Repo.delete()
    |> maybe_reconcile_engine()
  end

  @doc "Returns a register changeset for use in forms"
  def change_register(%Register{} = register, attrs \\ %{}) do
    Register.changeset(register, attrs)
  end

  @doc "Lists registers for a device"
  def list_registers_for_device(device_id) do
    query =
      from r in Register,
        where: r.device_id == ^device_id

    Repo.all(query)
  end

  @doc "Gets a single register by ID"
  def get_register!(id) do
    Repo.get!(Register, id)
  end

  @doc "Gets a register by ID without raising if not found"
  def get_register(id) do
    Repo.get(Register, id)
  end

  defp maybe_reconcile_engine({:ok, _record} = result) do
    ModbusMqtt.Engine.Reconciler.reconcile_now()
    result
  end

  defp maybe_reconcile_engine(result), do: result
end
