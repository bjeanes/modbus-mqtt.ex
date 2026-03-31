defmodule ModbusMqtt.Engine.RegisterReading do
  @moduledoc """
  Represents a register reading with raw bytes, interpreted value, and formatted output.
  """

  import Bitwise

  alias ModbusMqtt.Engine.RegisterValue

  @enforce_keys [:bytes, :value, :formatted]
  defstruct [:bytes, :value, :formatted]

  @type t :: %__MODULE__{
          bytes: [integer()],
          value: term(),
          formatted: String.t()
        }

  def from_modbus(values, register) when is_list(values) do
    value = RegisterValue.decode(values, register)

    %__MODULE__{
      bytes: bytes_from_values(values, register.type),
      value: value,
      formatted: to_string(value)
    }
  end

  defp bytes_from_values(values, type) when type in [:holding_register, :input_register] do
    Enum.flat_map(values, fn word ->
      [word >>> 8 &&& 0xFF, word &&& 0xFF]
    end)
  end

  defp bytes_from_values(values, _type), do: values
end
