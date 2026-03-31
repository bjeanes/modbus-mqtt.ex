defmodule ModbusMqtt.Engine.FieldInterpreter do
  @moduledoc """
  Reactive process that watches RegisterCache for changes to a field's
  dependency addresses and recomputes the semantic value.

  One FieldInterpreter per field. Subscribes to PubSub topics for the
  register type(s) it depends on. When notified of changes, reads fresh
  words from RegisterCache, decodes, applies semantics, and forwards
  the reading to Hub.
  """
  use GenServer
  require Logger

  alias ModbusMqtt.Engine.{FieldCodec, FieldReading, RegisterCache}

  defstruct [:device, :field, :destination, :pubsub, :last_bytes]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    state = struct!(__MODULE__, Map.put_new(args, :pubsub, ModbusMqtt.PubSub))

    # Subscribe to register cache updates for our register type
    Phoenix.PubSub.subscribe(
      state.pubsub,
      RegisterCache.register_topic(state.device.id, state.field.type)
    )

    # Try an initial read in case the cache is already warm
    state = maybe_emit(state)

    {:ok, state}
  end

  @impl true
  def handle_info({:registers_updated, device_id, register_type, changed_addresses}, state) do
    field = state.field

    state =
      if device_id == state.device.id and register_type == field.type and
           addresses_overlap?(field, changed_addresses) do
        maybe_emit(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp addresses_overlap?(field, changed_addresses) do
    addr = field.address + (field.address_offset || 0)
    count = FieldCodec.word_count(field)
    field_addresses = MapSet.new(addr..(addr + count - 1))
    Enum.any?(changed_addresses, &MapSet.member?(field_addresses, &1))
  end

  defp maybe_emit(state) do
    field = state.field
    addr = field.address + (field.address_offset || 0)
    count = FieldCodec.word_count(field)

    case RegisterCache.get_words(state.device.id, field.type, addr, count) do
      {:ok, values} ->
        reading = FieldReading.from_modbus(values, field)

        if reading.bytes != state.last_bytes do
          state.destination.put_value(state.device, field, reading)
          %{state | last_bytes: reading.bytes}
        else
          state
        end

      :error ->
        state
    end
  end
end
