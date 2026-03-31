defmodule ModbusMqtt.Engine.ScannerTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.Scanner

  defmodule FakeStatus do
    def clear_device_error(device), do: send(device.test_pid, {:status, :clear_error, device.id})

    def device_error(device, message) do
      send(device.test_pid, {:status, :device_error, device.id, message})
    end
  end

  defmodule FakeConnection do
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

  setup do
    :persistent_term.put({FakeConnection, :owner}, self())

    # Create a unique ETS table for RegisterCache per test
    table = :"register_cache_#{System.unique_integer([:positive])}"
    :ets.new(table, [:named_table, :set, :public, read_concurrency: true])

    on_exit(fn ->
      :persistent_term.erase({FakeConnection, :owner})
      :persistent_term.erase({FakeConnection, :reply})
    end)

    %{cache_table: table}
  end

  test "scans holding registers and writes to RegisterCache" do
    :persistent_term.put({FakeConnection, :reply}, {:ok, [100, 200, 300]})

    device = %{id: 10, unit: 2, name: "Meter", test_pid: self()}

    pid =
      start_supervised!(
        {Scanner,
         %{
           device: device,
           register_type: :holding_register,
           start_address: 40001,
           count: 3,
           poll_interval_ms: 30_000,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_holding_registers, 10, 2, 40001, 3}
    assert_receive {:status, :clear_error, 10}
  end

  test "scans input registers" do
    :persistent_term.put({FakeConnection, :reply}, {:ok, [42]})

    device = %{id: 11, unit: 1, name: "Sensor", test_pid: self()}

    pid =
      start_supervised!(
        {Scanner,
         %{
           device: device,
           register_type: :input_register,
           start_address: 5000,
           count: 1,
           poll_interval_ms: 30_000,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_input_registers, 11, 1, 5000, 1}
    assert_receive {:status, :clear_error, 11}
  end

  test "reports read errors without crashing" do
    :persistent_term.put({FakeConnection, :reply}, {:error, {:exit, :timeout}})

    device = %{id: 12, unit: 1, name: "Meter", test_pid: self()}

    pid =
      start_supervised!(
        {Scanner,
         %{
           device: device,
           register_type: :holding_register,
           start_address: 123,
           count: 1,
           poll_interval_ms: 30_000,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_holding_registers, 12, 1, 123, 1}
    assert_receive {:status, :device_error, 12, message}
    assert message =~ "Scan failed"
    assert Process.alive?(pid)
  end

  test "does not publish device_error for reconnecting errors" do
    :persistent_term.put({FakeConnection, :reply}, {:error, :device_not_running})

    device = %{id: 13, unit: 1, name: "Meter", test_pid: self()}

    pid =
      start_supervised!(
        {Scanner,
         %{
           device: device,
           register_type: :holding_register,
           start_address: 456,
           count: 1,
           poll_interval_ms: 30_000,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_holding_registers, 13, 1, 456, 1}
    refute_receive {:status, :device_error, 13, _message}, 100
    assert Process.alive?(pid)
  end
end
