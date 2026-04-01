defmodule ModbusMqtt.Client.HexModbus do
  @behaviour ModbusMqtt.Client

  @impl true
  def open(%{"protocol" => "tcp"} = config) do
    ip_str = Map.get(config, "host", "127.0.0.1")
    port = Map.get(config, "port", 502)

    with {:ok, ip} <- parse_ip(ip_str),
         true <- Code.ensure_loaded?(Modbus.Master) do
      Modbus.Master.start_link(ip: ip, port: port, timeout: 5000)
    else
      false -> {:error, :modbus_library_missing}
      {:error, _reason} = error -> error
    end
  end

  def open(%{"protocol" => "rtu"} = config) do
    tty = Map.get(config, "device_path", "/dev/ttyUSB0")
    baudrate = Map.get(config, "baud_rate", 9600)

    if Code.ensure_loaded?(Modbus.Master) do
      Modbus.Master.start_link(tty: tty, baudrate: baudrate, timeout: 5000)
    else
      {:error, :modbus_library_missing}
    end
  end

  def open(_), do: {:error, :unsupported_protocol}

  @impl true
  def close(pid) when is_pid(pid) do
    GenServer.stop(pid)
    :ok
  end

  def close(_), do: :ok

  @impl true
  def read_coils(pid, unit, address, count) do
    cmd = {:rc, unit, address, count}
    exec(pid, cmd)
  end

  @impl true
  def read_discrete_inputs(pid, unit, address, count) do
    cmd = {:ri, unit, address, count}
    exec(pid, cmd)
  end

  @impl true
  def read_holding_registers(pid, unit, address, count) do
    cmd = {:rhr, unit, address, count}
    exec(pid, cmd)
  end

  @impl true
  def read_input_registers(pid, unit, address, count) do
    cmd = {:rir, unit, address, count}
    exec(pid, cmd)
  end

  @impl true
  def write_coil(pid, unit, address, value) when value in [0, 1] do
    cmd = {:fc, unit, address, value}
    exec(pid, cmd)
  end

  @impl true
  def write_holding_registers(pid, unit, address, [single]) do
    cmd = {:phr, unit, address, single}
    exec(pid, cmd)
  end

  def write_holding_registers(pid, unit, address, values) when is_list(values) do
    cmd = {:phr, unit, address, values}
    exec(pid, cmd)
  end

  defp exec(pid, cmd) do
    try do
      Modbus.Master.exec(pid, cmd)
    catch
      :exit, term -> {:error, term}
    end
  end

  defp parse_ip(ip_str) do
    case ip_str |> to_string() |> String.to_charlist() |> :inet.parse_address() do
      {:ok, tuple} -> {:ok, tuple}
      {:error, reason} -> {:error, {:invalid_host, ip_str, reason}}
    end
  end
end
