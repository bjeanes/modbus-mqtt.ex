defmodule ModbusMqtt.Connections do
  @moduledoc """
  Context module for connection transport management.
  Handles CRUD operations on connections and queries that assemble
  connections with their associated device metadata and fields.
  """
  import Ecto.Query
  require Logger

  alias ModbusMqtt.Repo
  alias ModbusMqtt.Devices.Connection

  @doc "Lists all active connections with associated device and fields"
  def list_active_connections_with_device_fields do
    query =
      from c in Connection,
        where: c.active == true,
        preload: [device: [:fields]]

    query
    |> Repo.all()
    |> Enum.map(&connection_with_device_fields/1)
  end

  @doc "Gets a single active connection by ID with device and fields preloaded"
  def get_connection_with_device_fields!(id) do
    Repo.get!(Connection, id)
    |> Repo.preload(device: [:fields])
    |> connection_with_device_fields()
  end

  @doc "Gets a single active connection by ID without raising if not found"
  def get_connection_with_device_fields(id) do
    case Repo.get(Connection, id) do
      nil ->
        nil

      connection ->
        connection
        |> Repo.preload(device: [:fields])
        |> connection_with_device_fields()
    end
  end

  @doc "Creates a new connection for an existing device"
  def create_connection(device_id, attrs \\ %{}) do
    %Connection{}
    |> Connection.changeset(attrs)
    |> Ecto.Changeset.put_change(:device_id, device_id)
    |> Repo.insert()
    |> maybe_reconcile_engine()
  end

  @doc "Updates a connection"
  def update_connection(%Connection{} = connection, attrs) do
    connection
    |> Connection.changeset(attrs)
    |> Repo.update()
    |> maybe_reconcile_engine()
  end

  @doc "Deletes a connection"
  def delete_connection(%Connection{} = connection) do
    connection
    |> Repo.delete()
    |> maybe_reconcile_engine()
  end

  @doc "Returns a connection changeset for use in forms"
  def change_connection(%Connection{} = connection, attrs \\ %{}) do
    Connection.changeset(connection, attrs)
  end

  @doc "Lists connections for a device"
  def list_connections_for_device(device_id) do
    query =
      from c in Connection,
        where: c.device_id == ^device_id

    Repo.all(query)
  end

  @doc "Gets a single connection by ID"
  def get_connection!(id) do
    Repo.get!(Connection, id)
  end

  @doc "Gets a connection by ID without raising if not found"
  def get_connection(id) do
    Repo.get(Connection, id)
  end

  @doc "Lists all connections"
  def list_connections do
    Repo.all(Connection)
  end

  defp connection_with_device_fields(connection) do
    device = connection.device || %{}

    %{
      id: connection.id,
      connection_id: connection.id,
      device_id: connection.device_id,
      name: Map.get(device, :name),
      manufacturer: Map.get(device, :manufacturer),
      model_number: Map.get(device, :model_number),
      protocol: connection.protocol,
      base_topic: connection.base_topic,
      active: connection.active,
      unit: connection.unit,
      transport_config: connection.transport_config || %{},
      fields: Map.get(device, :fields, [])
    }
  end

  defp maybe_reconcile_engine({:ok, _record} = result) do
    ModbusMqtt.Engine.Reconciler.reconcile_now()
    result
  end

  defp maybe_reconcile_engine(result), do: result
end
