defmodule ModbusMqtt.Devices do
  @moduledoc """
  Context module for device metadata and field management.
  Handles device metadata CRUD, field management, and field lookup by topic.
  For connection management, see ModbusMqtt.Connections context.
  """
  import Ecto.Query
  require Logger

  alias ModbusMqtt.Repo
  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Devices.Topic
  alias ModbusMqtt.Connections

  @doc "Creates a new device metadata entry"
  def create_device(attrs \\ %{}) do
    %Device{}
    |> Device.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a device metadata entry"
  def update_device(%Device{} = device, attrs) do
    device
    |> Device.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a device metadata entry"
  def delete_device(%Device{} = device) do
    Repo.delete(device)
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

  @doc "Finds an active field by MQTT topic segments"
  def find_active_field_by_topic(device_topic, field_topic)
      when is_binary(device_topic) and is_binary(field_topic) do
    Connections.list_active_connections_with_device_fields()
    |> Enum.find_value(fn connection ->
      if Topic.key(connection) == device_topic do
        case Enum.find(connection.fields, &(&1.name == field_topic)) do
          nil -> nil
          field -> {connection, field}
        end
      end
    end)
  end

  defp maybe_reconcile_engine({:ok, _record} = result) do
    ModbusMqtt.Engine.Reconciler.reconcile_now()
    result
  end

  defp maybe_reconcile_engine(result), do: result
end
