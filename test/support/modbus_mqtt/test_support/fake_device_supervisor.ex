defmodule ModbusMqtt.TestSupport.FakeDeviceSupervisor do
  def whereis(device_id) do
    owner = :persistent_term.get({__MODULE__, :owner})
    pids = :persistent_term.get({__MODULE__, :pids}, %{})
    send(owner, {:whereis, device_id})
    Map.get(pids, device_id)
  end
end
