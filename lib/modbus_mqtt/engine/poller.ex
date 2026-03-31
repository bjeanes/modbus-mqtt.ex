defmodule ModbusMqtt.Engine.Poller do
  use GenServer
  require Logger

  alias ModbusMqtt.Engine.RegisterReading
  alias ModbusMqtt.Engine.RegisterValue
  alias ModbusMqtt.Mqtt.Status

  def start_link(%{device: _device, register: _register, destination: _destination} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(%{register: _reg} = args) do
    # Give the Connection process time to finish its handle_continue TCP dial
    # before firing the first poll.
    schedule_initial_poll(args)

    {:ok,
     Map.merge(
       %{
         connection: ModbusMqtt.Engine.Connection,
         destination: ModbusMqtt.Engine.Hub,
         status: Status,
         initial_poll_ms: nil
       },
       args
     )}
  end

  @impl true
  def handle_info(:poll, %{register: reg} = state) do
    Process.send_after(self(), :poll, reg.poll_interval_ms)
    read_register(state)
    {:noreply, state}
  end

  defp read_register(%{device: device, register: reg, connection: connection} = state) do
    addr = reg.address + (reg.address_offset || 0)
    unit = device.unit

    case reg.type do
      :holding_register ->
        count = RegisterValue.word_count(reg.data_type)
        res = connection.read_holding_registers(device.id, unit, addr, count)
        handle_response(res, state)

      :input_register ->
        count = RegisterValue.word_count(reg.data_type)
        res = connection.read_input_registers(device.id, unit, addr, count)
        handle_response(res, state)

      :coil ->
        res = connection.read_coils(device.id, unit, addr, 1)
        handle_response(res, state)

      :discrete_input ->
        res = connection.read_discrete_inputs(device.id, unit, addr, 1)
        handle_response(res, state)
    end
  end

  defp handle_response({:ok, values}, %{
         device: device,
         register: reg,
         destination: dest,
         status: status
       }) do
    reading = RegisterReading.from_modbus(values, reg)

    status.clear_device_error(device)

    # Send values directly to destination (usually Hub)
    dest.put_value(device, reg, reading)
  end

  defp handle_response({:error, reason}, %{device: device, register: reg, status: status}) do
    message =
      "Read failed for #{device.name} register #{reg.name} at address #{reg.address}: #{inspect(reason)}"

    if reconnecting_reason?(reason) do
      Logger.debug(message)
    else
      Logger.warning(message)
      status.device_error(device, message)
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

  defp schedule_initial_poll(_args) do
    Process.send_after(self(), :poll, Enum.random(100..500))
  end
end
