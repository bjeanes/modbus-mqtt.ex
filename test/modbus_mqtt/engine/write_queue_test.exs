defmodule ModbusMqtt.Engine.WriteQueueTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.WriteQueue

  defmodule FlakyWriter do
    def write(device, field, value) do
      send(device.test_pid, {:write_attempt, field.name, value})

      attempt = Agent.get_and_update(device.counter_pid, fn n -> {n, n + 1} end)

      if attempt == 0 do
        {:error, :timeout}
      else
        :ok
      end
    end
  end

  defmodule TimeoutWriter do
    def write(device, field, value) do
      send(device.test_pid, {:write_attempt, field.name, value})
      {:error, :timeout}
    end
  end

  test "retries timeout errors and emits status updates" do
    {:ok, counter_pid} = Agent.start_link(fn -> 0 end)

    queue_pid =
      start_supervised!(
        {WriteQueue,
         writer: FlakyWriter, retry_base_ms: 10, max_retry_ms: 20, max_attempts: 3, name: nil}
      )

    device = %{
      id: System.unique_integer([:positive]),
      unit: 1,
      test_pid: self(),
      counter_pid: counter_pid
    }

    field = %{name: "setpoint", type: :holding_register}

    Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{device.id}")

    assert :ok = WriteQueue.write(device, field, 42, server: queue_pid)

    assert_receive {:field_write_status, "setpoint", %{state: :pending}}
    assert_receive {:write_attempt, "setpoint", 42}
    assert_receive {:field_write_status, "setpoint", %{state: :retrying, reason: :timeout}}
    assert_receive {:write_attempt, "setpoint", 42}
    assert_receive {:field_write_status, "setpoint", %{state: :written}}

    Agent.stop(counter_pid)
  end

  test "discards pending retries when field value changes" do
    queue_pid =
      start_supervised!(
        {WriteQueue,
         writer: TimeoutWriter, retry_base_ms: 20, max_retry_ms: 40, max_attempts: 5, name: nil}
      )

    device = %{id: System.unique_integer([:positive]), unit: 1, test_pid: self()}
    field = %{name: "mode", type: :holding_register}

    Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{device.id}")

    assert :ok = WriteQueue.write(device, field, "auto", server: queue_pid)

    assert_receive {:field_write_status, "mode", %{state: :pending}}
    assert_receive {:write_attempt, "mode", "auto"}
    assert_receive {:field_write_status, "mode", %{state: :retrying}}

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device.id}",
      {:field_value_changed, device.id, "mode", "manual"}
    )

    assert_receive {:field_write_status, "mode", %{state: :discarded, reason: :value_changed}}
    refute_receive {:write_attempt, "mode", "auto"}, 80
  end

  test "newer write supersedes existing pending write for same field" do
    queue_pid =
      start_supervised!(
        {WriteQueue,
         writer: TimeoutWriter, retry_base_ms: 25, max_retry_ms: 50, max_attempts: 5, name: nil}
      )

    device = %{id: System.unique_integer([:positive]), unit: 1, test_pid: self()}
    field = %{name: "target", type: :holding_register}

    Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{device.id}")

    assert :ok = WriteQueue.write(device, field, 10, server: queue_pid)
    assert_receive {:field_write_status, "target", %{state: :pending}}

    assert :ok = WriteQueue.write(device, field, 11, server: queue_pid)
    assert_receive {:field_write_status, "target", %{state: :discarded, reason: :superseded}}
    assert_receive {:field_write_status, "target", %{state: :pending, requested_value: 11}}
  end

  test "returns error when queue server is not running" do
    device = %{id: System.unique_integer([:positive]), unit: 1, test_pid: self()}
    field = %{name: "target", type: :holding_register}

    assert {:error, :write_queue_not_running} =
             WriteQueue.write(device, field, 11, server: :missing_write_queue)
  end
end
