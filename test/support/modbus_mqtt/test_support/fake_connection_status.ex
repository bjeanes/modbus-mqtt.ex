defmodule ModbusMqtt.TestSupport.FakeConnectionStatus do
  def device_connecting(device), do: send(device.test_pid, {:status, :connecting, device.id})
  def device_connected(device), do: send(device.test_pid, {:status, :connected, device.id})

  def device_retrying_connection(device, attempt) do
    send(device.test_pid, {:status, :retrying_connection, device.id, attempt})
  end

  def device_connection_failed(device, message) do
    send(device.test_pid, {:status, :connection_failed, device.id, message})
  end

  def device_disconnected(device, reason) do
    send(device.test_pid, {:status, :disconnected, device.id, reason})
  end
end
