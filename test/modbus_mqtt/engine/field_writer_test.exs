defmodule ModbusMqtt.Engine.FieldWriterTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ModbusMqtt.Engine.FieldWriter

  defmodule FakeConnection do
    def write_coil(device_id, unit, address, value) do
      send(self(), {:write_coil, device_id, unit, address, value})
      :ok
    end

    def write_holding_registers(device_id, unit, address, values) do
      send(self(), {:write_holding_registers, device_id, unit, address, values})
      :ok
    end

    def read_coils(device_id, unit, address, count) do
      send(self(), {:read_coils, device_id, unit, address, count})
      {:ok, [1]}
    end

    def read_holding_registers(device_id, unit, address, count) do
      send(self(), {:read_holding_registers, device_id, unit, address, count})
      {:ok, List.duplicate(0xBEEF, count)}
    end
  end

  defmodule FakeConnectionReadbackFails do
    def write_coil(_device_id, _unit, _address, _value), do: :ok
    def write_holding_registers(_device_id, _unit, _address, _values), do: :ok
    def read_coils(_device_id, _unit, _address, _count), do: {:error, :not_connected}
    def read_holding_registers(_device_id, _unit, _address, _count), do: {:error, :not_connected}
  end

  defmodule FakeRegisterCache do
    def put_words(device_id, register_type, words) do
      send(self(), {:put_words, device_id, register_type, words})
      words
    end
  end

  test "writes coil values" do
    device = %{id: 11, unit: 1, name: "Boiler"}
    field = %{name: "enabled", type: :coil, address: 7, address_offset: 0, value_semantics: :raw}

    assert :ok =
             FieldWriter.write(device, field, true,
               connection: FakeConnection,
               register_cache: FakeRegisterCache
             )

    assert_receive {:write_coil, 11, 1, 7, 1}
    assert_receive {:read_coils, 11, 1, 7, 1}
    assert_receive {:put_words, 11, :coil, [{7, 1}]}
  end

  test "writes enum semantic value as register code" do
    device = %{id: 12, unit: 2, name: "Inverter"}

    field = %{
      name: "mode",
      type: :holding_register,
      data_type: :uint16,
      address: 13051,
      address_offset: 0,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :enum,
      enum_map: %{"0xAA" => "charge", "0xBB" => "discharge"}
    }

    assert :ok =
             FieldWriter.write(device, field, "discharge",
               connection: FakeConnection,
               register_cache: FakeRegisterCache
             )

    assert_receive {:write_holding_registers, 12, 2, 13051, [0xBB]}
    assert_receive {:read_holding_registers, 12, 2, 13051, 1}
    assert_receive {:put_words, 12, :holding_register, [{13051, 0xBEEF}]}
  end

  test "rejects out-of-range writes and logs an error" do
    device = %{id: 13, unit: 1, name: "Grid Meter"}

    field = %{
      name: "power",
      type: :holding_register,
      data_type: :uint16,
      address: 22,
      address_offset: 0,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw
    }

    log =
      capture_log(fn ->
        assert {:error, {:out_of_range, 100_000, 0, 65_535}} =
                 FieldWriter.write(device, field, 100_000, connection: FakeConnection)
      end)

    assert log =~ "Rejected out-of-range write"
    refute_receive {:write_holding_registers, _, _, _, _}
  end

  test "does not fail write when immediate readback fails" do
    device = %{id: 14, unit: 1, name: "Pump"}

    field = %{
      name: "speed",
      type: :holding_register,
      data_type: :uint16,
      address: 30,
      address_offset: 0,
      scale: 0,
      swap_words: false,
      swap_bytes: false,
      value_semantics: :raw
    }

    log =
      capture_log(fn ->
        assert :ok =
                 FieldWriter.write(device, field, 10,
                   connection: FakeConnectionReadbackFails,
                   register_cache: FakeRegisterCache
                 )
      end)

    assert log =~ "Write succeeded but immediate readback failed"
    refute_receive {:put_words, _, _, _}
  end
end
