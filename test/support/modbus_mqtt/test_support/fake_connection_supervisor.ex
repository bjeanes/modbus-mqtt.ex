defmodule ModbusMqtt.TestSupport.FakeConnectionSupervisor do
  def whereis(connection_id) do
    owner = :persistent_term.get({__MODULE__, :owner})
    pids = :persistent_term.get({__MODULE__, :pids}, %{})
    send(owner, {:whereis, connection_id})
    Map.get(pids, connection_id)
  end
end
