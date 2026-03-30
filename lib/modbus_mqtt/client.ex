defmodule ModbusMqtt.Client do
  @type connection :: term()
  @type bit_value :: 0 | 1
  @type error :: {:error, term()}

  @doc """
  Initialize the connection to the physical or logical Modbus device.
  The config argument will be the `transport_config` map combined with the `protocol`.
  """
  @callback open(config :: map()) :: {:ok, connection()} | error()

  @doc "Close the connection"
  @callback close(connection()) :: :ok

  @callback read_coils(connection(), unit :: integer(), address :: integer(), count :: integer()) ::
              {:ok, [bit_value()]} | error()
  @callback read_discrete_inputs(
              connection(),
              unit :: integer(),
              address :: integer(),
              count :: integer()
            ) :: {:ok, [bit_value()]} | error()
  @callback read_holding_registers(
              connection(),
              unit :: integer(),
              address :: integer(),
              count :: integer()
            ) :: {:ok, [integer()]} | error()
  @callback read_input_registers(
              connection(),
              unit :: integer(),
              address :: integer(),
              count :: integer()
            ) :: {:ok, [integer()]} | error()
end
