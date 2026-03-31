defmodule ModbusMqtt.Engine.Connection do
  @moduledoc """
  A GenServer that wraps the underlying Modbus protocol client connection.
  Registers itself in the Registry so pollers can find it by device_id.
  """
  use GenServer, restart: :transient
  require Logger

  alias ModbusMqtt.Mqtt.Status

  def start_link({device, opts}) when is_list(opts) do
    start_link(device, opts)
  end

  def start_link(device) do
    start_link(device, [])
  end

  def start_link(device, opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, {device, opts}, name: via_tuple(device.id))
  end

  defp via_tuple(device_id) do
    {:via, Registry, {ModbusMqtt.Registry, {__MODULE__, device_id}}}
  end

  @doc "Gets the PID of the connection for the given device ID"
  def whereis(device_id) do
    case Registry.lookup(ModbusMqtt.Registry, {__MODULE__, device_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl true
  def init({device, opts}) do
    Process.flag(:trap_exit, true)

    # Defer synchronous Modbus connection block until after init returns to prevent
    # exceeding the default 5000ms GenServer startup timeout, which breaks the supervisor tree
    # when hardware endpoints are disconnected or unreachable on the network.
    state = %{
      device: device,
      client: Keyword.get(opts, :client, ModbusMqtt.Client.HexModbus),
      status: Keyword.get(opts, :status, Status),
      conn_pid: nil,
      retry_count: 0,
      max_retries: Keyword.get(opts, :max_retries, 5),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, 1000),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, 30_000)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(
        :connect,
        %{
          device: device,
          client: client_module,
          status: status,
          retry_count: retry_count,
          max_retries: max_retries,
          base_delay_ms: base_delay_ms,
          max_delay_ms: max_delay_ms
        } = state
      ) do
    # Merge protocol and transport_config
    config =
      Map.merge(device.transport_config || %{}, %{"protocol" => to_string(device.protocol)})

    endpoint = endpoint_summary(config)

    if retry_count == 0 do
      status.device_connecting(device)

      Logger.info(
        "Connecting Modbus device #{device.id} (#{device.name}) via #{device.protocol} to #{endpoint}"
      )
    else
      status.device_retrying_connection(device, retry_count)

      Logger.info(
        "Retrying Modbus device #{device.id} (#{device.name}) connection (attempt #{retry_count} of #{max_retries}) to #{endpoint}"
      )
    end

    case open_connection(client_module, config) do
      {:ok, conn_pid} ->
        Logger.info(
          "Modbus device #{device.id} (#{device.name}) connected successfully to #{endpoint}"
        )

        status.device_connected(device)

        # Link to the underlying connection so if it crashes, we crash and are restarted.
        if is_pid(conn_pid) do
          Process.link(conn_pid)
        end

        {:noreply, %{state | conn_pid: conn_pid, retry_count: 0}}

      {:error, reason} ->
        message =
          "Modbus device #{device.id} (#{device.name}) failed to connect to #{endpoint}: #{format_reason(reason)}"

        Logger.error(message)

        if retry_count >= max_retries do
          Logger.error(
            "Modbus device #{device.id} (#{device.name}) exceeded max retries (#{max_retries}), stopping"
          )

          status.device_connection_failed(device, message)
          {:stop, reason, state}
        else
          next_retry = retry_count + 1
          delay_ms = calculate_backoff_delay(next_retry, base_delay_ms, max_delay_ms)

          Logger.info(
            "Scheduling retry for Modbus device #{device.id} (#{device.name}) in #{delay_ms}ms"
          )

          Process.send_after(self(), :retry_connect, delay_ms)
          {:noreply, %{state | retry_count: next_retry}}
        end
    end
  end

  @impl true
  def handle_info(
        {:EXIT, conn_pid, reason},
        %{conn_pid: conn_pid, device: device, status: status} = state
      ) do
    message =
      "Modbus device #{device.id} (#{device.name}) connection dropped: #{format_reason(reason)}"

    Logger.error(message)
    status.device_disconnected(device, message)
    {:stop, reason, %{state | conn_pid: nil}}
  end

  @impl true
  def handle_info(:retry_connect, state) do
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info(msg, %{device: device} = state) do
    Logger.debug(
      "Modbus device #{device.id} (#{device.name}) received unexpected message: #{inspect(msg)}"
    )

    {:noreply, state}
  end

  # API wrappers that delegate to the configured client
  def read_holding_registers(device_id, unit, address, count) do
    call_device(device_id, {:read_holding_registers, unit, address, count})
  end

  def read_coils(device_id, unit, address, count) do
    call_device(device_id, {:read_coils, unit, address, count})
  end

  def read_discrete_inputs(device_id, unit, address, count) do
    call_device(device_id, {:read_discrete_inputs, unit, address, count})
  end

  def read_input_registers(device_id, unit, address, count) do
    call_device(device_id, {:read_input_registers, unit, address, count})
  end

  # Exponential backoff calculation with jitter
  defp calculate_backoff_delay(retry_count, base_delay_ms, max_delay_ms) when retry_count > 0 do
    # Exponential backoff: delay = min(base * 2^(retry_count-1), max_delay_ms)
    exponential_delay = base_delay_ms * trunc(:math.pow(2, retry_count - 1))
    capped_delay = min(exponential_delay, max_delay_ms)

    # Add jitter: ±10% of the delay to avoid thundering herd
    jitter_range = div(capped_delay, 10)
    jitter = :rand.uniform(jitter_range * 2) - jitter_range
    max(100, capped_delay + jitter)
  end

  @impl true
  # Guard all reads/writes: if handle_continue hasn't finished dialing yet,
  # conn_pid is nil — return :not_connected so the Poller logs a warning
  # rather than raising and crashing the Connection process.
  def handle_call(_msg, _from, %{conn_pid: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(
        {:read_holding_registers, unit, address, count},
        _from,
        %{client: client, conn_pid: conn_pid} = state
      ) do
    {:reply, client.read_holding_registers(conn_pid, unit, address, count), state}
  end

  def handle_call(
        {:read_coils, unit, address, count},
        _from,
        %{client: client, conn_pid: conn_pid} = state
      ) do
    {:reply, client.read_coils(conn_pid, unit, address, count), state}
  end

  def handle_call(
        {:read_discrete_inputs, unit, address, count},
        _from,
        %{client: client, conn_pid: conn_pid} = state
      ) do
    {:reply, client.read_discrete_inputs(conn_pid, unit, address, count), state}
  end

  def handle_call(
        {:read_input_registers, unit, address, count},
        _from,
        %{client: client, conn_pid: conn_pid} = state
      ) do
    {:reply, client.read_input_registers(conn_pid, unit, address, count), state}
  end

  @impl true
  def terminate(
        reason,
        %{client: client, conn_pid: conn_pid, device: device, status: status} = _state
      ) do
    if conn_pid do
      status.device_disconnected(device, termination_error(reason))
    end

    if client && conn_pid do
      client.close(conn_pid)
    end

    :ok
  end

  defp open_connection(client_module, config) do
    timeout_ms = Map.get(config, "connect_timeout_ms", 8_000)
    task = Task.async(fn -> safe_open(client_module, config) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :connect_timeout}
    end
  end

  defp safe_open(client_module, config) do
    try do
      client_module.open(config)
    rescue
      exception -> {:error, {exception.__struct__, Exception.message(exception)}}
    catch
      :exit, reason -> {:error, {:exit, reason}}
    end
  end

  defp call_device(device_id, request) do
    case whereis(device_id) do
      nil ->
        {:error, :device_not_running}

      pid ->
        try do
          GenServer.call(pid, request)
        catch
          :exit, {:noproc, _details} -> {:error, :device_not_running}
          :exit, {reason, _details} -> {:error, {:exit, reason}}
          :exit, reason -> {:error, {:exit, reason}}
        end
    end
  end

  defp endpoint_summary(config) do
    case config["protocol"] do
      "tcp" -> "#{Map.get(config, "host", "127.0.0.1")}:#{Map.get(config, "port", 502)}"
      "rtu" -> "#{Map.get(config, "device_path", "/dev/ttyUSB0")}"
      protocol -> "#{protocol} transport"
    end
  end

  defp termination_error(reason) when reason in [:normal, :shutdown], do: nil
  defp termination_error(reason), do: format_reason(reason)

  defp format_reason(reason) do
    inspect(reason, pretty: true, limit: :infinity)
  end
end
