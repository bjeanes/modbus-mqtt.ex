defmodule ModbusMqtt.Engine.Scanner do
  @moduledoc """
  Periodically reads a contiguous range of Modbus registers and writes
  raw words into RegisterCache.

  Unlike the old Poller (1 GenServer per field), a Scanner may cover
  multiple fields that share a contiguous address range and register type.

  The Scanner is purely concerned with physical reads — it has no knowledge
  of field semantics, scaling, or MQTT topics.
  """
  use GenServer
  require Logger

  alias ModbusMqtt.Engine.RegisterCache

  defstruct [
    :device,
    :register_type,
    :start_address,
    :count,
    :poll_interval_ms,
    :connection,
    :status,
    :initial_poll_ms
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    state = struct!(__MODULE__, args)
    schedule_initial_poll(state)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, state.poll_interval_ms)
    scan(state)
    {:noreply, state}
  end

  defp scan(%{device: device, register_type: type, start_address: addr, count: count} = state) do
    unit = device.unit

    # Logger.debug("Scanning #{device.name} #{type} #{addr}+#{count} (unit #{unit})")

    result =
      case type do
        :holding_register ->
          state.connection.read_holding_registers(device.id, unit, addr, count)

        :input_register ->
          state.connection.read_input_registers(device.id, unit, addr, count)

        :coil ->
          state.connection.read_coils(device.id, unit, addr, count)

        :discrete_input ->
          state.connection.read_discrete_inputs(device.id, unit, addr, count)
      end

    handle_response(result, state)
  end

  defp handle_response({:ok, values}, state) do
    words =
      values
      |> Enum.with_index()
      |> Enum.map(fn {word, offset} -> {state.start_address + offset, word} end)

    RegisterCache.put_words(state.device.id, state.register_type, words)

    state.status.clear_device_error(state.device)
  end

  defp handle_response({:error, reason}, state) do
    message =
      "Scan failed for #{state.device.name} #{state.register_type} " <>
        "#{state.start_address}+#{state.count}: #{inspect(reason)}"

    if reconnecting_reason?(reason) do
      Logger.debug(message)
    else
      Logger.warning(message)
      state.status.device_error(state.device, message)
    end
  end

  defp reconnecting_reason?(:not_connected), do: true
  defp reconnecting_reason?(:device_not_running), do: true
  defp reconnecting_reason?({:exit, :noproc}), do: true
  defp reconnecting_reason?(_), do: false

  defp schedule_initial_poll(%{initial_poll_ms: :manual}), do: :ok

  defp schedule_initial_poll(%{initial_poll_ms: poll_ms}) when is_integer(poll_ms) do
    Process.send_after(self(), :poll, poll_ms)
  end

  defp schedule_initial_poll(_state) do
    Process.send_after(self(), :poll, Enum.random(100..500))
  end
end
