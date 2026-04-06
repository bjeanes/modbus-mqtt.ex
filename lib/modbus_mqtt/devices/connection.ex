defmodule ModbusMqtt.Devices.Connection do
  use Ecto.Schema
  import Ecto.Changeset

  alias ModbusMqtt.Devices.Topic

  schema "connections" do
    field :protocol, Ecto.Enum, values: [:tcp, :rtu, :custom], default: :tcp
    field :base_topic, :string
    field :active, :boolean, default: true
    field :unit, :integer, default: 1
    field :transport_config, :map, default: %{}

    belongs_to :device, ModbusMqtt.Devices.Device

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:protocol, :base_topic, :active, :unit, :transport_config])
    |> update_change(:base_topic, &Topic.normalize/1)
    |> validate_required([:protocol, :base_topic, :active, :unit, :transport_config])
    |> validate_number(:unit, greater_than: 0)
    |> Topic.validate_segment(:base_topic)
    |> unique_constraint(:base_topic, name: :connections_base_topic_index)
  end
end
