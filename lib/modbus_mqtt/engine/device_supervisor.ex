defmodule ModbusMqtt.Engine.DeviceSupervisor do
  @moduledoc """
  A standard Supervisor that manages the children for a single Modbus Device.
  This includes:
    1. The Modbus connection itself.
    2. Scanner processes for contiguous register ranges.
    3. FieldInterpreter processes for each field.
  """
  use Supervisor

  alias ModbusMqtt.Engine.FieldCodec

  def start_link(device) do
    name = via_tuple(device.id)
    Supervisor.start_link(__MODULE__, device, name: name)
  end

  @doc "Gets the PID of the device supervisor for the given device ID"
  def whereis(device_id) do
    case Registry.lookup(ModbusMqtt.Registry, {__MODULE__, device_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(device_id) do
    {:via, Registry, {ModbusMqtt.Registry, {__MODULE__, device_id}}}
  end

  @impl true
  def init(device) do
    connection_opts = [status: ModbusMqtt.Mqtt.Status]
    fields = device.fields || []

    # 1. Connection process
    children = [
      {ModbusMqtt.Engine.Connection, {device, connection_opts}}
    ]

    # 2. Derive Scanner specs from fields
    scanners = derive_scanners(device, fields)

    # 3. One FieldInterpreter per field
    interpreters =
      for field <- fields do
        %{
          id: {ModbusMqtt.Engine.FieldInterpreter, device.id, field.id},
          start:
            {ModbusMqtt.Engine.FieldInterpreter, :start_link,
             [
               %{
                 device: device,
                 field: field,
                 destination: ModbusMqtt.Engine.Hub
               }
             ]}
        }
      end

    children = children ++ scanners ++ interpreters

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  Derives the minimal set of Scanner child specs from a list of fields.

  Groups fields by register type, then merges overlapping/adjacent address
  ranges into contiguous scans. The poll interval for each scan is the
  minimum across all fields in the range.
  """
  def derive_scanners(device, fields) do
    fields
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn {register_type, type_fields} ->
      type_fields
      |> Enum.map(fn field ->
        addr = field.address + (field.address_offset || 0)
        count = FieldCodec.word_count(field)
        {addr, addr + count - 1, field.poll_interval_ms}
      end)
      |> merge_ranges()
      |> Enum.with_index()
      |> Enum.map(fn {{start_addr, end_addr, interval}, idx} ->
        count = end_addr - start_addr + 1

        %{
          id: {ModbusMqtt.Engine.Scanner, device.id, register_type, idx},
          start:
            {ModbusMqtt.Engine.Scanner, :start_link,
             [
               %{
                 device: device,
                 register_type: register_type,
                 start_address: start_addr,
                 count: count,
                 poll_interval_ms: interval,
                 connection: ModbusMqtt.Engine.Connection,
                 status: ModbusMqtt.Mqtt.Status
               }
             ]}
        }
      end)
    end)
  end

  @coalesce_gap 4

  # Merge overlapping or adjacent address ranges, taking the minimum poll interval for coalesced ranges.
  #
  # Each input is {start_addr, end_addr, interval}.
  #
  # Gaps of up to @coalesce_gap are considered adjacent for coalescing purposes, to avoid excessive fragmentation.
  defp merge_ranges(ranges) do
    ranges
    |> Enum.sort_by(fn {start, _end, _interval} -> start end)
    |> Enum.reduce([], fn {s, e, interval}, acc ->
      case acc do
        [{ps, pe, pi} | rest] when s <= pe + @coalesce_gap + 1 ->
          [{ps, max(pe, e), min(pi, interval)} | rest]

        _ ->
          [{s, e, interval} | acc]
      end
    end)
    |> Enum.reverse()
  end
end
