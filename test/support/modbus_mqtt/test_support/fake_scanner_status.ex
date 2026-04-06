defmodule ModbusMqtt.TestSupport.FakeScannerStatus do
  def clear_device_error(connection),
    do: send(connection.test_pid, {:status, :clear_error, connection.id})

  def device_error(connection, message) do
    send(connection.test_pid, {:status, :device_error, connection.id, message})
  end
end
