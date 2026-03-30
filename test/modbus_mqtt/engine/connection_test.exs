defmodule ModbusMqtt.Engine.ConnectionTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.Connection

  defmodule FakeStatus do
    def device_connecting(device), do: send(device.test_pid, {:status, :connecting, device.id})
    def device_connected(device), do: send(device.test_pid, {:status, :connected, device.id})

    def device_connection_failed(device, message) do
      send(device.test_pid, {:status, :connection_failed, device.id, message})
    end

    def device_disconnected(device, reason) do
      send(device.test_pid, {:status, :disconnected, device.id, reason})
    end
  end

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

    defp read(pid, kind, unit, address, count) do
      config = Agent.get(pid, & &1)
      send(config["test_pid"], {kind, unit, address, count})
      {:ok, config["read_values"] || [123]}
    end
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

    {:ok, pid} = Connection.start_link({device, [client: FakeClient, status: FakeStatus]})
    assert_receive {:status, :connecting, ^device_id}
    assert_receive {:status, :connection_failed, ^device_id, message}
    assert message =~ "failed to connect"
    assert_receive {:EXIT, ^pid, :boom}
  end
end
