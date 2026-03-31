defmodule ModbusMqtt.Devices.Field do
  use Ecto.Schema
  import Ecto.Changeset

  @enum_register_types [:holding_register, :input_register]
  @numeric_data_types [:int16, :uint16, :int32, :uint32, :float32]
  @unit_presets ["°C", "°F", "%", "V", "A", "W", "kWh", "Hz"]

  schema "fields" do
    field :name, :string

    field :type, Ecto.Enum,
      values: [:coil, :discrete_input, :input_register, :holding_register],
      default: :holding_register

    field :data_type, Ecto.Enum,
      values: [:int16, :uint16, :int32, :uint32, :float32, :string, :bool],
      default: :uint16

    field :address, :integer
    field :address_offset, :integer, default: 0
    field :poll_interval_ms, :integer, default: 5000
    field :writable, :boolean, default: false
    field :scale, :integer, default: 0
    field :swap_words, :boolean, default: false
    field :swap_bytes, :boolean, default: false
    field :value_semantics, Ecto.Enum, values: [:raw, :enum], default: :raw
    field :enum_map, :map, default: %{}
    field :unit, :string
    field :bit_mask, :integer
    field :length, :integer

    belongs_to :device, ModbusMqtt.Devices.Device

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(field, attrs) do
    field
    |> cast(attrs, [
      :name,
      :type,
      :data_type,
      :address,
      :address_offset,
      :poll_interval_ms,
      :writable,
      :scale,
      :swap_words,
      :swap_bytes,
      :value_semantics,
      :enum_map,
      :unit,
      :bit_mask,
      :length,
      :device_id
    ])
    |> validate_required([
      :name,
      :type,
      :data_type,
      :address,
      :address_offset,
      :poll_interval_ms,
      :writable,
      :scale,
      :swap_words,
      :swap_bytes,
      :value_semantics,
      :enum_map,
      :device_id
    ])
    |> normalize_unit()
    |> validate_enum_semantics()
    |> validate_bitmap_field()
    |> validate_string_length_field()
    |> validate_measurement_unit()
    |> fill_length()
  end

  @doc "Returns common measurement unit presets for numeric fields"
  @spec unit_presets() :: [String.t()]
  def unit_presets, do: @unit_presets

  @doc """
  Parses enum map keys from decimal (`100`), hex (`0xAA`), or binary (`0b1010`).
  """
  @spec parse_enum_key(integer() | String.t()) :: {:ok, non_neg_integer()} | {:error, atom()}
  def parse_enum_key(value) when is_integer(value) do
    validate_enum_code(value)
  end

  def parse_enum_key(value) when is_binary(value) do
    trimmed = String.trim(value)

    parsed =
      cond do
        String.starts_with?(trimmed, "0x") or String.starts_with?(trimmed, "0X") ->
          parse_prefixed(trimmed, 2, 16)

        String.starts_with?(trimmed, "0b") or String.starts_with?(trimmed, "0B") ->
          parse_prefixed(trimmed, 2, 2)

        true ->
          parse_full_integer(trimmed, 10)
      end

    case parsed do
      {:ok, code} -> validate_enum_code(code)
      {:error, _reason} -> {:error, :invalid_enum_key}
    end
  end

  def parse_enum_key(_value), do: {:error, :invalid_enum_key}

  defp validate_string_length_field(changeset) do
    case get_field(changeset, :data_type) do
      :string ->
        changeset
        |> validate_required([:length], message: "is required for string fields")
        |> validate_number(:length, greater_than: 0)

      _ ->
        changeset
    end
  end

  defp fill_length(changeset) do
    case get_field(changeset, :data_type) do
      :string ->
        changeset

      data_type when not is_nil(data_type) ->
        put_change(changeset, :length, fixed_type_word_count(data_type))

      _ ->
        changeset
    end
  end

  defp fixed_type_word_count(dt) when dt in [:float32, :int32, :uint32], do: 2
  defp fixed_type_word_count(_), do: 1

  @integer_data_types [:uint16, :int16, :uint32, :int32]

  defp validate_bitmap_field(changeset) do
    case get_field(changeset, :bit_mask) do
      nil ->
        changeset

      _bit_mask ->
        changeset
        |> validate_inclusion(:data_type, @integer_data_types,
          message: "must be an integer type when bit_mask is set"
        )
        |> validate_inclusion(:type, @enum_register_types,
          message: "must be input_register or holding_register when bit_mask is set"
        )
        |> validate_number(:scale, equal_to: 0, message: "must be 0 when bit_mask is set")
        |> validate_number(:bit_mask, greater_than: 0, message: "must be greater than 0")
    end
  end

  defp normalize_unit(changeset) do
    case get_change(changeset, :unit) do
      nil ->
        changeset

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          put_change(changeset, :unit, nil)
        else
          put_change(changeset, :unit, trimmed)
        end

      _value ->
        changeset
    end
  end

  defp validate_measurement_unit(changeset) do
    unit = get_field(changeset, :unit)

    if is_nil(unit) do
      changeset
    else
      changeset
      |> validate_length(:unit, max: 16)
      |> validate_change(:unit, fn :unit, _value ->
        if unit_allowed?(changeset) do
          []
        else
          [unit: "can only be set for numeric raw fields"]
        end
      end)
    end
  end

  defp unit_allowed?(changeset) do
    get_field(changeset, :data_type) in @numeric_data_types and
      get_field(changeset, :value_semantics, :raw) == :raw and
      is_nil(get_field(changeset, :bit_mask))
  end

  defp validate_enum_semantics(changeset) do
    case get_field(changeset, :value_semantics, :raw) do
      :enum ->
        changeset
        |> validate_enum_map_field()
        |> validate_inclusion(:data_type, [:uint16],
          message: "must be uint16 when value_semantics is enum"
        )
        |> validate_inclusion(:type, @enum_register_types,
          message: "must be input_register or holding_register when value_semantics is enum"
        )
        |> validate_number(:scale, equal_to: 0)

      :raw ->
        changeset
    end
  end

  defp validate_enum_map_field(changeset) do
    :enum_map
    |> validate_enum_map(get_field(changeset, :enum_map))
    |> Enum.reduce(changeset, fn {field, message}, acc -> add_error(acc, field, message) end)
  end

  defp validate_enum_map(field, enum_map) when is_map(enum_map) do
    errors =
      if map_size(enum_map) == 0 do
        [{field, "must contain at least one entry"}]
      else
        []
      end

    {errors, _seen_codes} =
      Enum.reduce(enum_map, {errors, %{}}, fn {key, label}, {acc_errors, seen_codes} ->
        acc_errors =
          if valid_enum_label?(label) do
            acc_errors
          else
            [{field, "contains an invalid label for key #{inspect(key)}"} | acc_errors]
          end

        case parse_enum_key(key) do
          {:ok, code} ->
            case Map.fetch(seen_codes, code) do
              :error ->
                {acc_errors, Map.put(seen_codes, code, key)}

              {:ok, existing_key} ->
                {[
                   {field,
                    "contains duplicate numeric key mappings for #{inspect(existing_key)} and #{inspect(key)}"}
                   | acc_errors
                 ], seen_codes}
            end

          {:error, _reason} ->
            {[{field, "contains an invalid key #{inspect(key)}"} | acc_errors], seen_codes}
        end
      end)

    Enum.reverse(errors)
  end

  defp validate_enum_map(field, _enum_map), do: [{field, "must be a map"}]

  defp valid_enum_label?(label) when is_binary(label), do: String.trim(label) != ""
  defp valid_enum_label?(_label), do: false

  defp parse_prefixed(value, offset, base) do
    value
    |> String.slice(offset..-1//1)
    |> parse_full_integer(base)
  end

  defp parse_full_integer(value, _base) when value in [nil, ""], do: {:error, :invalid_enum_key}

  defp parse_full_integer(value, base) do
    case Integer.parse(value, base) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_enum_key}
    end
  end

  defp validate_enum_code(code) when code >= 0 and code <= 0xFFFF, do: {:ok, code}
  defp validate_enum_code(_code), do: {:error, :invalid_enum_key}
end
