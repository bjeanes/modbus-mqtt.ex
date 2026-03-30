defmodule ModbusMqtt.Engine.Supervisor do
  @moduledoc """
  The core DynamicSupervisor for managing Modbus device connections.
  When a configuration changes in the Database, this supervisor can be 
  directed to start, stop, or restart the child DeviceSupervisor trees dynamically.
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
  Starts a ModbusMqtt.Engine.DeviceSupervisor tree for the given device configuration.
  """
  def start_device(device) do
    spec = {ModbusMqtt.Engine.DeviceSupervisor, device}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a running device supervisor tree.
  """
  def stop_device(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
