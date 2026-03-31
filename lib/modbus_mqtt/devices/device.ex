defmodule ModbusMqtt.Devices.Device do
  use Ecto.Schema
  import Ecto.Changeset

  alias ModbusMqtt.Devices.Topic

  schema "devices" do
    field :name, :string
    field :protocol, Ecto.Enum, values: [:tcp, :rtu, :custom], default: :tcp
    field :base_topic, :string
    field :active, :boolean, default: true
    field :unit, :integer, default: 1
    field :transport_config, :map, default: %{}

    has_many :fields, ModbusMqtt.Devices.Field

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [:name, :protocol, :base_topic, :active, :unit, :transport_config])
    |> update_change(:base_topic, &Topic.normalize/1)
    |> validate_required([:name, :protocol, :active, :unit, :transport_config])
    |> Topic.validate_segment(:base_topic)
    |> check_constraint(:base_topic, name: :devices_base_topic_single_segment)
    |> unique_constraint(:base_topic, name: :devices_base_topic_index)
  end
end
