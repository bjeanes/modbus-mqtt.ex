defmodule ModbusMqtt.Engine.PollerTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.Poller

  defmodule FakeStatus do
    def clear_device_error(device), do: send(device.test_pid, {:status, :clear_error, device.id})

    def device_error(device, message) do
      send(device.test_pid, {:status, :device_error, device.id, message})
    end
  end

  defmodule FakeDestination do
    def put_value(device, register, value) do
      send(device.test_pid, {:put_value, device.id, register.name, value})
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

    on_exit(fn ->
      :persistent_term.erase({FakeConnection, :owner})
      :persistent_term.erase({FakeConnection, :reply})
    end)

    :ok
  end

  test "polls, decodes, scales, and forwards values" do
    :persistent_term.put({FakeConnection, :reply}, {:ok, [12]})

    device = %{id: 10, unit: 2, name: "Meter", test_pid: self()}

    register = %{
      name: "power",
      address: 40001,
      address_offset: 1,
      data_type: :uint16,
      poll_interval_ms: 30_000,
      scale: 1,
      swap_words: false,
      swap_bytes: false,
      type: :holding_register
    }

    pid =
      start_supervised!(
        {Poller,
         %{
           device: device,
           register: register,
           destination: FakeDestination,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_holding_registers, 10, 2, 40002, 1}
    assert_receive {:status, :clear_error, 10}
    assert_receive {:put_value, 10, "power", 120.0}
  end

  test "reports read errors without crashing" do
    :persistent_term.put({FakeConnection, :reply}, {:error, :device_not_running})

    device = %{id: 11, unit: 1, name: "Meter", test_pid: self()}

    register = %{
      name: "power",
      address: 123,
      address_offset: 0,
      data_type: :uint16,
      poll_interval_ms: 30_000,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      type: :holding_register
    }

    pid =
      start_supervised!(
        {Poller,
         %{
           device: device,
           register: register,
           destination: FakeDestination,
           connection: FakeConnection,
           status: FakeStatus,
           initial_poll_ms: :manual
         }}
      )

    send(pid, :poll)

    assert_receive {:read_holding_registers, 11, 1, 123, 1}
    assert_receive {:status, :device_error, 11, message}
    assert message =~ "Read failed"
    assert Process.alive?(pid)
  end
end
