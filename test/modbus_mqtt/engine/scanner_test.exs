defmodule ModbusMqtt.Engine.ScannerTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.RegisterCache
  alias ModbusMqtt.Engine.Scanner
  alias ModbusMqtt.TestSupport.FakeScannerConnection, as: FakeConnection
  alias ModbusMqtt.TestSupport.FakeScannerStatus, as: FakeStatus

  setup do
    :persistent_term.put({FakeConnection, :owner}, self())

    if :ets.whereis(:modbus_mqtt_register_cache) == :undefined do
      :ets.new(:modbus_mqtt_register_cache, [:named_table, :set, :public, read_concurrency: true])
    end

    on_exit(fn ->
      :persistent_term.erase({FakeConnection, :owner})
      :persistent_term.erase({FakeConnection, :reply})
    end)

    :ok
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
    assert {:ok, [100, 200, 300]} = RegisterCache.get_words(10, :holding_register, 40001, 3)
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
    assert {:ok, [42]} = RegisterCache.get_words(11, :input_register, 5000, 1)
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
