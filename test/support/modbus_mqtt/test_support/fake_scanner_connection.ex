defmodule ModbusMqtt.TestSupport.FakeScannerConnection do
  def read_coils(device_id, unit, address, count),
    do: read(:read_coils, device_id, unit, address, count)

  def read_discrete_inputs(device_id, unit, address, count),
    do: read(:read_discrete_inputs, device_id, unit, address, count)

  def read_holding_registers(device_id, unit, address, count),
    do: read(:read_holding_registers, device_id, unit, address, count)

  def read_input_registers(device_id, unit, address, count),
    do: read(:read_input_registers, device_id, unit, address, count)

  defp read(kind, device_id, unit, address, count) do
    owner = :persistent_term.get({__MODULE__, :owner})
    reply = :persistent_term.get({__MODULE__, :reply})
    send(owner, {kind, device_id, unit, address, count})
    reply
  end
end
