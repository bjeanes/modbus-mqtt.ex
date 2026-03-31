defmodule ModbusMqtt.Engine.FieldReading do
  @moduledoc """
  Represents a field reading with raw bytes, interpreted value, and formatted output.
  """

  import Bitwise

  alias ModbusMqtt.Engine.FieldSemantics
  alias ModbusMqtt.Engine.FieldCodec

  @enforce_keys [:bytes, :decoded, :value, :formatted]
  defstruct [:bytes, :decoded, :value, :formatted]

  @type t :: %__MODULE__{
          bytes: [integer()],
          decoded: term(),
          value: term(),
          formatted: String.t()
        }

  def from_modbus(values, field) when is_list(values) do
    decoded = FieldCodec.decode(values, field)
    value = FieldSemantics.to_value(decoded, field)

    %__MODULE__{
      bytes: bytes_from_values(values, field.type),
      decoded: decoded,
      value: value,
      formatted: FieldSemantics.format(value)
    }
  end

  defp bytes_from_values(values, type) when type in [:holding_register, :input_register] do
    Enum.flat_map(values, fn word ->
      [word >>> 8 &&& 0xFF, word &&& 0xFF]
    end)
  end

  defp bytes_from_values(values, _type), do: values
end
