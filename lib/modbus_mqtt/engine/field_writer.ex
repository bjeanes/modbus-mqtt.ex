defmodule ModbusMqtt.Engine.FieldWriter do
  @moduledoc """
  Encodes and writes field values to Modbus using semantic field values as input.
  """

  require Logger

  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Engine.{Connection, FieldCodec, FieldSemantics, RegisterCache}

  def write(device, field, value, opts \\ []) do
    connection = Keyword.get(opts, :connection, Connection)
    register_cache = Keyword.get(opts, :register_cache, RegisterCache)

    cond do
      not Field.writable?(field) ->
        {:error, :not_writable}

      true ->
        do_write(connection, register_cache, device, field, value)
    end
  end

  defp do_write(connection, register_cache, device, field, value) do
    with {:ok, semantic_value} <- FieldSemantics.from_value(value, field),
         {:ok, encoded} <- FieldCodec.encode_write(semantic_value, field),
         :ok <- write_to_device(connection, device, field, encoded) do
      maybe_refresh_after_write(connection, register_cache, device, field)
      :ok
    else
      {:error, {:out_of_range, written_value, min, max}} = error ->
        Logger.error(
          "Rejected out-of-range write for #{device.name}:#{field.name} (#{inspect(written_value)} not in #{min}..#{max})"
        )

        error

      {:error, reason} = error ->
        Logger.error("Rejected write for #{device.name}:#{field.name}: #{inspect(reason)}")

        error
    end
  end

  defp write_to_device(connection, device, field, [value]) when field.type == :coil do
    address = field.address + (field.address_offset || 0)
    connection.write_coil(device.id, device.unit, address, value)
  end

  defp write_to_device(connection, device, field, values) when field.type == :holding_register do
    address = field.address + (field.address_offset || 0)
    connection.write_holding_registers(device.id, device.unit, address, values)
  end

  defp write_to_device(_connection, _device, _field, _values) do
    {:error, :not_writable}
  end

  defp maybe_refresh_after_write(connection, register_cache, device, field)
       when field.type in [:coil, :holding_register] do
    address = field.address + (field.address_offset || 0)
    count = readback_count(field)

    result =
      case field.type do
        :coil ->
          connection.read_coils(device.id, device.unit, address, count)

        :holding_register ->
          connection.read_holding_registers(device.id, device.unit, address, count)
      end

    case result do
      {:ok, values} ->
        words =
          values
          |> Enum.with_index()
          |> Enum.map(fn {value, offset} -> {address + offset, value} end)

        register_cache.put_words(device.id, field.type, words)
        :ok

      {:error, reason} ->
        Logger.warning(
          "Write succeeded but immediate readback failed for #{device.name}:#{field.name}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp maybe_refresh_after_write(_connection, _register_cache, _device, _field), do: :ok

  defp readback_count(%{type: :coil}), do: 1
  defp readback_count(field), do: FieldCodec.word_count(field)
end
