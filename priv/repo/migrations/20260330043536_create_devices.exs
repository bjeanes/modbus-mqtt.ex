defmodule ModbusMqtt.Repo.Migrations.CreateDevices do
  use Ecto.Migration

  def change do
    create table(:devices) do
      add :name, :string, null: false
      add :protocol, :string, null: false, default: "tcp"
      add :base_topic, :string, null: false
      add :active, :boolean, default: true, null: false
      add :unit, :integer, null: false, default: 1
      add :transport_config, :map, null: false, default: "{}"

      timestamps(type: :utc_datetime)
    end
  end
end
