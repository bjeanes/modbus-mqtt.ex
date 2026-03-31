defmodule ModbusMqtt.Engine.DeviceSupervisor do
  @moduledoc """
  A standard Supervisor that manages the children for a single Modbus Device.
  This includes:
    1. The Modbus connection itself.
    2. The Poller processes for its registers.
    3. (Future) The TopicSubscriber for handling inbound writes via MQTT.
  """
  use Supervisor

  def start_link(device) do
    # You could register this under a via tuple as well if needed.
    name = via_tuple(device.id)
    Supervisor.start_link(__MODULE__, device, name: name)
  end

  @doc "Gets the PID of the device supervisor for the given device ID"
  def whereis(device_id) do
    case Registry.lookup(ModbusMqtt.Registry, {__MODULE__, device_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(device_id) do
    {:via, Registry, {ModbusMqtt.Registry, {__MODULE__, device_id}}}
  end

  @impl true
  def init(device) do
    connection_opts = [status: ModbusMqtt.Mqtt.Status]

    # 1. Connection process
    children = [
      {ModbusMqtt.Engine.Connection, {device, connection_opts}}
    ]

    # 2. Add precisely 1 Poller process per register for simplicity and modular isolation
    pollers =
      for reg <- device.registers || [] do
        %{
          id: {ModbusMqtt.Engine.Poller, device.id, reg.id},
          start:
            {ModbusMqtt.Engine.Poller, :start_link,
             [
               %{
                 device: device,
                 register: reg,
                 destination: ModbusMqtt.Engine.Hub,
                 connection: ModbusMqtt.Engine.Connection,
                 status: ModbusMqtt.Mqtt.Status
               }
             ]}
        }
      end

    children = children ++ pollers

    # One-for-all strategy implies that if the connection dies, we want the pollers
    # to restart, and if pollers crash continuously, we restart the connection too.
    # Rest_for_one pushes restarts downwards (e.g. if the connection dies, the pollers restart).
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
