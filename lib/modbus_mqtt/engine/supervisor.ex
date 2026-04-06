defmodule ModbusMqtt.Engine.Supervisor do
  @moduledoc """
  The core DynamicSupervisor for managing Modbus connection trees.
  When a configuration changes in the database, this supervisor can be
  directed to start, stop, or restart the child ConnectionSupervisor trees dynamically.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 60
    )
  end

  @doc """
  Starts a ModbusMqtt.Engine.ConnectionSupervisor tree for the given connection.
  """
  def start_connection(connection) do
    spec = {ModbusMqtt.Engine.ConnectionSupervisor, connection}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a running connection supervisor tree.
  """
  def stop_connection(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
