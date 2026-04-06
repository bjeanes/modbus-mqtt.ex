defmodule ModbusMqtt.TestSupport.FakeConnectionStatus do
  def device_connecting(connection),
    do: send(connection.test_pid, {:status, :connecting, connection.id})

  def device_connected(connection),
    do: send(connection.test_pid, {:status, :connected, connection.id})

  def device_retrying_connection(connection, attempt) do
    send(connection.test_pid, {:status, :retrying_connection, connection.id, attempt})
  end

  def device_connection_failed(connection, message) do
    send(connection.test_pid, {:status, :connection_failed, connection.id, message})
  end

  def device_disconnected(connection, reason) do
    send(connection.test_pid, {:status, :disconnected, connection.id, reason})
  end
end
