defmodule ModbusMqtt.TestSupport.FakeScannerStatus do
  def clear_device_error(device), do: send(device.test_pid, {:status, :clear_error, device.id})

  def device_error(device, message) do
    send(device.test_pid, {:status, :device_error, device.id, message})
  end
end
