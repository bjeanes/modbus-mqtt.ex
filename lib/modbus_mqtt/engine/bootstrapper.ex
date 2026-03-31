defmodule ModbusMqtt.Engine.Bootstrapper do
  @moduledoc """
  A simple task that queries active devices from the database and
  plugs them into the Engine DynamicSupervisor on boot.
  """
  use Task
  require Logger

  def start_link(_arg) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    # Delay slightly to ensure Repo is fully ready, or rely on Supervison order
    # (Since this starts after Repo, it should be fine)

    devices = ModbusMqtt.Devices.list_active_devices_with_registers()

    Logger.info("Bootstrapper found #{length(devices)} active device(s), starting engines...")

    Enum.each(devices, fn device ->
      case ModbusMqtt.Engine.Supervisor.start_device(device) do
        {:ok, _pid} ->
          Logger.info("Started Engine for #{device.name}")

        {:error, reason} ->
          Logger.error("Failed to start Engine for #{device.name}: #{inspect(reason)}")
      end
    end)
  end
end
