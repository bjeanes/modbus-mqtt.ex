defmodule ModbusMqtt.Devices.Register do
  use Ecto.Schema
  import Ecto.Changeset

  schema "registers" do
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

    belongs_to :device, ModbusMqtt.Devices.Device

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(register, attrs) do
    register
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
      :device_id
    ])
  end
end
