defmodule ModbusMqtt.Engine.ConnectionTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.Connection
  alias ModbusMqtt.TestSupport.FakeConnectionStatus, as: FakeStatus

  defmodule FakeClient do
    @behaviour ModbusMqtt.Client

    def open(%{"open_result" => {:error, reason}}), do: {:error, reason}

    def open(config) do
      send(config["test_pid"], {:client_open, config})
      Agent.start_link(fn -> config end)
    end

    def close(pid) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {:client_close, config["device_id"]})
      Agent.stop(pid)
      :ok
    end

    def read_coils(pid, unit, address, count), do: read(pid, :read_coils, unit, address, count)

    def read_discrete_inputs(pid, unit, address, count),
      do: read(pid, :read_discrete_inputs, unit, address, count)

    def read_holding_registers(pid, unit, address, count),
      do: read(pid, :read_holding_registers, unit, address, count)

    def read_input_registers(pid, unit, address, count),
      do: read(pid, :read_input_registers, unit, address, count)

    def write_coil(pid, unit, address, value),
      do: write(pid, :write_coil, unit, address, [value])

    def write_holding_registers(pid, unit, address, values),
      do: write(pid, :write_holding_registers, unit, address, values)

    defp read(pid, kind, unit, address, count) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {kind, unit, address, count})
      {:ok, config["read_values"] || [123]}
    end

    defp write(pid, kind, unit, address, values) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {kind, unit, address, values})
      :ok
    end
  end

  defmodule FakeClientReadDisconnected do
    @behaviour ModbusMqtt.Client

    def open(config), do: Agent.start_link(fn -> config end)

    def close(pid) do
      Agent.stop(pid)
      :ok
    end

    def read_coils(_pid, _unit, _address, _count), do: {:error, :enotconn}
    def read_discrete_inputs(_pid, _unit, _address, _count), do: {:error, :enotconn}
    def read_holding_registers(_pid, _unit, _address, _count), do: {:error, :enotconn}
    def read_input_registers(_pid, _unit, _address, _count), do: {:error, :enotconn}
    def write_coil(_pid, _unit, _address, _value), do: :ok
    def write_holding_registers(_pid, _unit, _address, _values), do: :ok
  end

  defmodule FakeClientWriteDisconnected do
    @behaviour ModbusMqtt.Client

    def open(config), do: Agent.start_link(fn -> config end)

    def close(pid) do
      Agent.stop(pid)
      :ok
    end

    def read_coils(_pid, _unit, _address, _count), do: {:ok, []}
    def read_discrete_inputs(_pid, _unit, _address, _count), do: {:ok, []}
    def read_holding_registers(_pid, _unit, _address, _count), do: {:ok, [0]}
    def read_input_registers(_pid, _unit, _address, _count), do: {:ok, [0]}
    def write_coil(_pid, _unit, _address, _value), do: {:error, :enotconn}
    def write_holding_registers(_pid, _unit, _address, _values), do: {:error, :enotconn}
  end

  defmodule FakeClientWithRetries do
    @behaviour ModbusMqtt.Client

    def open(config) do
      call_count_pid = config["call_count_pid"]
      current_count = Agent.get(call_count_pid, & &1)
      Agent.update(call_count_pid, &(&1 + 1))

      if current_count < 2 do
        {:error, :temporary_failure}
      else
        Agent.start_link(fn -> config end)
      end
    end

    def close(pid) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {:client_close, config["device_id"]})
      Agent.stop(pid)
      :ok
    end

    def read_holding_registers(pid, unit, address, count) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {:read_holding_registers, unit, address, count})
      {:ok, config["read_values"] || [123]}
    end

    def read_coils(_pid, _unit, _address, _count), do: {:ok, []}
    def read_discrete_inputs(_pid, _unit, _address, _count), do: {:ok, []}
    def read_input_registers(_pid, _unit, _address, _count), do: {:ok, []}
    def write_coil(_pid, _unit, _address, _value), do: :ok
    def write_holding_registers(_pid, _unit, _address, _values), do: :ok
  end

  defmodule FakeClientAlwaysFails do
    @behaviour ModbusMqtt.Client

    def open(_config) do
      {:error, :permanent_failure}
    end

    def close(_pid), do: :ok
    def read_holding_registers(_pid, _unit, _address, _count), do: {:ok, []}
    def read_coils(_pid, _unit, _address, _count), do: {:ok, []}
    def read_discrete_inputs(_pid, _unit, _address, _count), do: {:ok, []}
    def read_input_registers(_pid, _unit, _address, _count), do: {:ok, []}
    def write_coil(_pid, _unit, _address, _value), do: :ok
    def write_holding_registers(_pid, _unit, _address, _values), do: :ok
  end

  test "returns an error when the connection process is absent" do
    assert Connection.read_holding_registers(-1, 1, 0, 1) == {:error, :device_not_running}
  end

  test "connects and delegates reads through the configured client" do
    device_id = System.unique_integer([:positive])

    device = %{
      id: device_id,
      name: "Test Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "device_id" => device_id,
        "test_pid" => self(),
        "read_values" => [77]
      }
    }

    pid = start_supervised!({Connection, {device, client: FakeClient, status: FakeStatus}})

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:client_open, _config}
    assert_receive {:status, :connected, ^device_id}

    assert Connection.read_holding_registers(device_id, 1, 40001, 1) == {:ok, [77]}
    assert_receive {:read_holding_registers, 1, 40001, 1}

    assert Connection.write_coil(device_id, 1, 2, 1) == :ok
    assert_receive {:write_coil, 1, 2, [1]}

    assert Connection.write_holding_registers(device_id, 1, 500, [1, 2]) == :ok
    assert_receive {:write_holding_registers, 1, 500, [1, 2]}

    GenServer.stop(pid)
    assert_receive {:client_close, ^device_id}
  end

  test "reports connection failures through the injected status module" do
    trap_exit? = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, trap_exit?) end)

    device_id = System.unique_integer([:positive])

    device = %{
      id: device_id,
      name: "Broken Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "open_result" => {:error, :boom}
      }
    }

    {:ok, pid} =
      Connection.start_link({device, [client: FakeClient, status: FakeStatus, max_retries: 0]})

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :connection_failed, ^device_id, message}
    assert message =~ "failed to connect"
    assert_receive {:EXIT, ^pid, :boom}
  end

  test "retries connection with exponential backoff on temporary failure" do
    trap_exit? = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, trap_exit?) end)

    device_id = System.unique_integer([:positive])

    # State variable to track how many times open was called
    {:ok, call_count} = Agent.start_link(fn -> 0 end)

    device = %{
      id: device_id,
      name: "Retry Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "device_id" => device_id,
        "test_pid" => self(),
        "call_count_pid" => call_count
      }
    }

    {:ok, pid} =
      Connection.start_link(
        {device,
         [
           client: FakeClientWithRetries,
           status: FakeStatus,
           max_retries: 5,
           base_delay_ms: 100,
           max_delay_ms: 500
         ]}
      )

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :retrying_connection, ^device_id, 1}, 1000
    assert_receive {:status, :retrying_connection, ^device_id, 2}, 1000
    assert_receive {:status, :connected, ^device_id}, 1000

    # Verify the connection is working
    assert Connection.read_holding_registers(device_id, 1, 0, 1) == {:ok, [123]}

    GenServer.stop(pid)
    assert_receive {:client_close, ^device_id}

    Agent.stop(call_count)
  end

  test "stops after exceeding max retries" do
    trap_exit? = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, trap_exit?) end)

    device_id = System.unique_integer([:positive])

    device = %{
      id: device_id,
      name: "Always Broken Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "device_id" => device_id,
        "test_pid" => self()
      }
    }

    {:ok, pid} =
      Connection.start_link(
        {device,
         [
           client: FakeClientAlwaysFails,
           status: FakeStatus,
           max_retries: 2,
           base_delay_ms: 50,
           max_delay_ms: 100
         ]}
      )

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :retrying_connection, ^device_id, 1}, 2000
    assert_receive {:status, :retrying_connection, ^device_id, 2}, 2000
    assert_receive {:status, :connection_failed, ^device_id, _message}, 2000
    assert_receive {:EXIT, ^pid, :permanent_failure}
  end

  test "stops connection on fatal enotconn read error" do
    trap_exit? = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, trap_exit?) end)

    device_id = System.unique_integer([:positive])

    device = %{
      id: device_id,
      name: "Disconnected Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "device_id" => device_id,
        "test_pid" => self()
      }
    }

    {:ok, pid} =
      Connection.start_link(
        {device,
         [
           client: FakeClientReadDisconnected,
           status: FakeStatus,
           max_retries: 0
         ]}
      )

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :connected, ^device_id}

    assert Connection.read_holding_registers(device_id, 1, 0, 1) == {:error, :enotconn}
    assert_receive {:status, :disconnected, ^device_id, _reason}, 1000
    assert_receive {:EXIT, ^pid, {:fatal_read_error, :enotconn}}, 1000
  end

  test "stops connection on fatal enotconn write error" do
    trap_exit? = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, trap_exit?) end)

    device_id = System.unique_integer([:positive])

    device = %{
      id: device_id,
      name: "Write-Disconnected Device",
      protocol: :tcp,
      unit: 1,
      test_pid: self(),
      transport_config: %{
        "host" => "127.0.0.1",
        "device_id" => device_id,
        "test_pid" => self()
      }
    }

    {:ok, pid} =
      Connection.start_link(
        {device,
         [
           client: FakeClientWriteDisconnected,
           status: FakeStatus,
           max_retries: 0
         ]}
      )

    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :connected, ^device_id}

    assert Connection.write_holding_registers(device_id, 1, 0, [42]) == {:error, :enotconn}
    assert_receive {:status, :disconnected, ^device_id, _reason}, 1000
    assert_receive {:EXIT, ^pid, {:fatal_write_error, :enotconn}}, 1000
  end
end
