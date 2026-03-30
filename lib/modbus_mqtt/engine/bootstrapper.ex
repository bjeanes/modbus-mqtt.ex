defmodule ModbusMqtt.Engine.Bootstrapper do
  @moduledoc """
  A simple task that queries active devices from the database and
  plugs them into the Engine DynamicSupervisor on boot.
  """
  use Task
  import Ecto.Query
  require Logger

  alias ModbusMqtt.Repo
  alias ModbusMqtt.Devices.Device

  def start_link(_arg) do
    Task.start_link(__MODULE__, :run, [])
  end

  def run do
    # Delay slightly to ensure Repo is fully ready, or rely on Supervison order
    # (Since this starts after Repo, it should be fine)

    query =
      from d in Device,
        where: d.active == true,
        preload: [:registers]

    devices = Repo.all(query)

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
