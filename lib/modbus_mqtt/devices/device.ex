defmodule ModbusMqtt.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  schema "devices" do
    field :name, :string
    field :manufacturer, :string
    field :model_number, :string

    has_many :fields, ModbusMqtt.Devices.Field
    has_many :connections, ModbusMqtt.Devices.Connection

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:name, :manufacturer, :model_number])
    |> validate_required([:name])
    |> validate_length(:manufacturer, max: 120)
    |> validate_length(:model_number, max: 255)
  end
end
