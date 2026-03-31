# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias ModbusMqtt.Repo
alias ModbusMqtt.Devices.{Device, Register}

# Clean existing to ensure idempotency when running seeds multiple times
Repo.delete_all(Register)
Repo.delete_all(Device)

device =
  Repo.insert!(%Device{
    name: "Sungrow SH10.0RS",
    protocol: :tcp,
    base_topic: "sungrow",
    active: true,
    unit: 1,
    transport_config: %{
      "host" => "10.10.20.216",
      "port" => 502
    }
  })

registers = [
  %{address: 5017, data_type: :uint32, name: "dc_power", swap_words: true, poll_interval_ms: 500},
  %{
    address: 13034,
    data_type: :uint32,
    name: "active_power",
    swap_words: true,
    poll_interval_ms: 500
  },
  %{address: 4990, name: "serial_number", data_type: :string, length: 10},
  %{
    address: 5008,
    data_type: :int16,
    name: "internal_temperature",
    poll_interval_ms: 60_000,
    scale: -1
  },
  %{
    address: 5001,
    data_type: :uint16,
    name: "nominal_output_power",
    poll_interval_ms: 60_000,
    scale: 2
  },
  %{
    address: 13008,
    data_type: :int32,
    name: "load_power",
    swap_words: true,
    poll_interval_ms: 500
  },
  %{
    address: 13010,
    data_type: :int32,
    name: "export_power",
    swap_words: true,
    poll_interval_ms: 500
  },
  %{
    address: 13020,
    name: "battery_voltage",
    poll_interval_ms: 3000,
    data_type: :uint16,
    scale: -1
  },
  %{address: 13022, name: "battery_power", poll_interval_ms: 500},
  %{address: 13021, name: "battery_current", poll_interval_ms: 500, data_type: :int16, scale: -1},
  %{address: 13023, name: "battery_level", poll_interval_ms: 60_000, scale: -1},
  %{address: 13024, name: "battery_health", poll_interval_ms: 600_000, scale: -1},
  %{address: 5036, name: "grid_frequency", poll_interval_ms: 60_000, scale: -2},
  %{address: 5019, name: "phase_a_voltage", poll_interval_ms: 60_000, scale: -1},
  %{address: 13031, name: "phase_a_current", poll_interval_ms: 60_000, scale: -1},
  %{address: 5011, name: "mppt1_voltage", scale: -1},
  %{address: 5012, name: "mppt1_current", scale: -1},
  %{address: 5013, name: "mppt2_voltage", scale: -1},
  %{address: 5014, name: "mppt2_current", scale: -1},
  %{
    type: :holding_register,
    address: 13058,
    name: "max_soc",
    poll_interval_ms: 90_000,
    scale: -1
  },
  %{
    type: :holding_register,
    address: 13059,
    name: "min_soc",
    poll_interval_ms: 90_000,
    scale: -1
  },
  %{type: :holding_register, address: 13100, name: "battery_reserve"},
  %{type: :holding_register, address: 33148, name: "forced_battery_power", scale: 1},
  %{address: 13002, data_type: :uint16, name: "daily_pv_generation", scale: -1},
  %{address: 13003, data_type: :uint32, swap_words: true, name: "total_pv_generation", scale: -1},
  %{address: 13005, data_type: :uint16, name: "daily_export_energy", scale: -1},
  %{address: 13006, data_type: :uint32, swap_words: true, name: "total_export_energy", scale: -1},
  %{address: 13012, data_type: :uint16, name: "daily_battery_charge_energy", scale: -1},
  %{
    address: 13013,
    data_type: :uint32,
    swap_words: true,
    name: "total_battery_charge_energy",
    scale: -1
  },
  %{address: 13026, data_type: :uint16, name: "daily_battery_discharge_energy", scale: -1},
  %{
    address: 13027,
    data_type: :uint32,
    swap_words: true,
    name: "total_battery_discharge_energy",
    scale: -1
  },
  %{address: 13017, data_type: :uint16, name: "daily_direct_energy_consumption", scale: -1},
  %{
    address: 13018,
    data_type: :uint32,
    swap_words: true,
    name: "total_direct_energy_consumption",
    scale: -1
  },
  %{address: 5003, data_type: :uint16, name: "daily_output_energy", scale: -1},
  %{address: 5004, data_type: :uint32, swap_words: true, name: "total_output_energy", scale: -1},
  %{address: 13029, data_type: :uint16, name: "daily_self_consumption_rate", scale: -1},
  %{
    address: 13051,
    data_type: :uint16,
    type: :holding_register,
    name: "battery_mode",
    poll_interval_ms: 1000,
    value_semantics: :enum,
    enum_map: %{
      "0xAA" => "charge",
      "0xBB" => "discharge",
      "0xCC" => "stop"
    }
  },
  %{address: 13036, data_type: :uint16, name: "daily_import_energy", scale: -1},
  %{address: 13037, data_type: :uint32, swap_words: true, name: "total_import_energy", scale: -1},
  %{address: 13040, data_type: :uint16, name: "daily_charge_energy", scale: -1},
  %{address: 13041, data_type: :uint32, swap_words: true, name: "total_charge_energy", scale: -1}
]

for reg <- registers do
  data_type = Map.get(reg, :data_type, :uint16)

  length =
    Map.get(reg, :length) ||
      case data_type do
        dt when dt in [:int32, :uint32, :float32] -> 2
        _ -> 1
      end

  Repo.insert!(%Register{
    device_id: device.id,
    name: reg[:name],
    type: Map.get(reg, :type, :input_register),
    data_type: data_type,
    address: reg[:address],
    address_offset: -1,
    poll_interval_ms: Map.get(reg, :poll_interval_ms, 5000),
    writable: Map.get(reg, :type) == :holding_register,
    scale: Map.get(reg, :scale, 0),
    swap_words: Map.get(reg, :swap_words, false),
    swap_bytes: Map.get(reg, :swap_bytes, false),
    value_semantics: Map.get(reg, :value_semantics, :raw),
    enum_map: Map.get(reg, :enum_map, %{}),
    length: length
  })
end
