# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias ModbusMqtt.Repo
alias ModbusMqtt.Devices
alias ModbusMqtt.Devices.{Device, Field}
import Bitwise

# Clean existing to ensure idempotency when running seeds multiple times
Repo.delete_all(Field)
Repo.delete_all(Device)

device =
  Repo.insert!(%Device{
    name: "Sungrow Hybrid Inverter",
    protocol: :tcp,
    base_topic: "sungrow",
    active: true,
    unit: 1,
    transport_config: %{
      "host" => "10.10.20.216",
      "port" => 502
    }
  })

fields = [
  %{
    address: 5017,
    data_type: :uint32,
    name: "dc_power",
    swap_words: true,
    poll_interval_ms: 500,
    unit: "W"
  },
  %{
    address: 13034,
    data_type: :uint32,
    name: "active_power",
    swap_words: true,
    poll_interval_ms: 500,
    unit: "W"
  },
  %{address: 4990, name: "serial_number", data_type: :string, length: 10},
  %{
    address: 5008,
    data_type: :int16,
    name: "internal_temperature",
    poll_interval_ms: 60_000,
    scale: -1,
    unit: "°C"
  },
  %{
    address: 5000,
    name: "model",
    data_type: :uint16,
    value_semantics: :enum,
    enum_map: %{
      "0xD17" => "SH3.0RS",
      "0xD0D" => "SH3.6RS",
      "0xD18" => "SH4.0RS",
      "0xD0F" => "SH5.0RS",
      "0xD10" => "SH6.0RS",
      "0xD1A" => "SH8.0RS",
      "0xD1B" => "SH10RS",
      "0xE00" => "SH5.0RT",
      "0xE01" => "SH6.0RT",
      "0xE02" => "SH8.0RT",
      "0xE03" => "SH10RT",
      "0xE10" => "SH5.0RT-20",
      "0xE11" => "SH6.0RT-20",
      "0xE12" => "SH8.0RT-20",
      "0xE13" => "SH10RT-20",
      "0xE0C" => "SH5.0RT-V112",
      "0xE0D" => "SH6.0RT-V112",
      "0xE0E" => "SH8.0RT-V112",
      "0xE0F" => "SH10RT-V112",
      "0xE08" => "SH5.0RT-V122",
      "0xE09" => "SH6.0RT-V122",
      "0xE0A" => "SH8.0RT-V122",
      "0xE0B" => "SH10RT-V122",
      "0xE20" => "SH5T",
      "0xE21" => "SH6T",
      "0xE22" => "SH8T",
      "0xE23" => "SH10T",
      "0xE24" => "SH12T",
      "0xE25" => "SH15T",
      "0xE26" => "SH20T",
      "0xE28" => "SH25T",
      "0xD27" => "MG5RL",
      "0xD28" => "MG6RL"
    }
  },
  %{
    address: 5001,
    data_type: :uint16,
    name: "nominal_output_power",
    scale: 2,
    unit: "W"
  },
  %{
    name: "battery_capacity",
    address: 5639,
    data_type: :uint16,
    scale: -2,
    poll_interval_ms: 600_000,
    unit: "kWh"
  },
  %{
    address: 13025,
    data_type: :int16,
    name: "battery_temperature",
    poll_interval_ms: 60_000,
    scale: -1,
    unit: "°C"
  },
  %{
    address: 13008,
    data_type: :int32,
    name: "load_power",
    swap_words: true,
    poll_interval_ms: 500,
    unit: "W"
  },
  %{
    address: 13010,
    data_type: :int32,
    name: "export_power",
    swap_words: true,
    poll_interval_ms: 500,
    unit: "W"
  },
  %{
    address: 13020,
    name: "battery_voltage",
    poll_interval_ms: 3000,
    data_type: :uint16,
    scale: -1,
    unit: "V"
  },
  %{
    address: 5214,
    data_type: :int32,
    name: "battery_power",
    swap_words: true,
    poll_interval_ms: 500,
    unit: "W"
  },
  %{
    address: 13021,
    name: "battery_current",
    poll_interval_ms: 500,
    data_type: :int16,
    scale: -1,
    unit: "A"
  },
  %{address: 13023, name: "battery_level", scale: -1, unit: "%"},
  %{address: 13024, name: "battery_health", scale: -1, unit: "%"},
  %{address: 5242, name: "grid_frequency", poll_interval_ms: 1000, scale: -2, unit: "Hz"},
  %{address: 5019, name: "phase_a_voltage", poll_interval_ms: 1000, scale: -1, unit: "V"},
  %{address: 13031, name: "phase_a_current", poll_interval_ms: 1000, scale: -1, unit: "A"},
  %{address: 5011, name: "mppt1_voltage", poll_interval_ms: 1000, scale: -1, unit: "V"},
  %{address: 5012, name: "mppt1_current", poll_interval_ms: 1000, scale: -1, unit: "A"},
  %{address: 5013, name: "mppt2_voltage", poll_interval_ms: 1000, scale: -1, unit: "V"},
  %{address: 5014, name: "mppt2_current", poll_interval_ms: 1000, scale: -1, unit: "A"},
  %{
    type: :holding_register,
    address: 13058,
    name: "max_soc",
    scale: -1,
    unit: "%"
  },
  %{
    type: :holding_register,
    address: 13059,
    name: "min_soc",
    scale: -1,
    unit: "%"
  },
  %{type: :holding_register, address: 13100, name: "battery_reserve", unit: "%"},
  %{type: :holding_register, address: 33148, name: "forced_battery_power", scale: 1, unit: "W"},
  %{address: 13002, data_type: :uint16, name: "daily_pv_generation", scale: -1, unit: "kWh"},
  %{
    address: 13003,
    data_type: :uint32,
    swap_words: true,
    name: "total_pv_generation",
    scale: -1,
    unit: "kWh"
  },
  %{address: 13005, data_type: :uint16, name: "daily_export_energy", scale: -1, unit: "kWh"},
  %{
    address: 13006,
    data_type: :uint32,
    swap_words: true,
    name: "total_export_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13012,
    data_type: :uint16,
    name: "daily_battery_charge_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13013,
    data_type: :uint32,
    swap_words: true,
    name: "total_battery_charge_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13026,
    data_type: :uint16,
    name: "daily_battery_discharge_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13027,
    data_type: :uint32,
    swap_words: true,
    name: "total_battery_discharge_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13017,
    data_type: :uint16,
    name: "daily_direct_energy_consumption",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13018,
    data_type: :uint32,
    swap_words: true,
    name: "total_direct_energy_consumption",
    scale: -1,
    unit: "kWh"
  },
  %{address: 5003, data_type: :uint16, name: "daily_output_energy", scale: -1, unit: "kWh"},
  %{
    address: 5004,
    data_type: :uint32,
    swap_words: true,
    name: "total_output_energy",
    scale: -1,
    unit: "kWh"
  },
  %{
    address: 13029,
    data_type: :uint16,
    name: "daily_self_consumption_rate",
    scale: -1,
    unit: "%"
  },
  %{
    name: "ems_mode",
    address: 13050,
    data_type: :uint16,
    type: :holding_register,
    value_semantics: :enum,
    enum_map: %{
      "0" => "self-consumption",
      "2" => "forced",
      "3" => "external",
      "4" => "vpp"
    }
  },
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
  %{address: 13036, data_type: :uint16, name: "daily_import_energy", scale: -1, unit: "kWh"},
  %{
    address: 13037,
    data_type: :uint32,
    swap_words: true,
    name: "total_import_energy",
    scale: -1,
    unit: "kWh"
  },
  %{address: 13040, data_type: :uint16, name: "daily_charge_energy", scale: -1, unit: "kWh"},
  %{
    address: 13041,
    data_type: :uint32,
    swap_words: true,
    name: "total_charge_energy",
    scale: -1,
    unit: "kWh"
  },

  # Bitmap fields: multiple boolean fields derived from the same underlying register (13001)
  %{address: 13001, data_type: :uint16, name: "state_generating", bit_mask: 1 <<< 0},
  %{address: 13001, data_type: :uint16, name: "state_charging", bit_mask: 1 <<< 1},
  %{address: 13001, data_type: :uint16, name: "state_discharging", bit_mask: 1 <<< 2},
  %{address: 13001, data_type: :uint16, name: "state_positive_load_power", bit_mask: 1 <<< 3},
  %{address: 13001, data_type: :uint16, name: "state_exporting", bit_mask: 1 <<< 4},
  %{address: 13001, data_type: :uint16, name: "state_importing", bit_mask: 1 <<< 5},
  %{address: 13001, data_type: :uint16, name: "state_negative_load_power", bit_mask: 1 <<< 7}
]

for field_attrs <- fields do
  attrs =
    field_attrs
    |> Map.put_new(:type, :input_register)
    |> Map.put_new(:address_offset, -1)

  {:ok, _} = Devices.create_field(device.id, attrs)
end
