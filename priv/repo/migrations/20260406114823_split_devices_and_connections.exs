defmodule ModbusMqtt.Repo.Migrations.SplitDevicesAndConnections do
  use Ecto.Migration
  import Ecto.Query

  def up do
    create table(:connections) do
      add :device_id, references(:devices, on_delete: :delete_all), null: false
      add :protocol, :string, null: false, default: "tcp"
      add :base_topic, :string, null: false
      add :active, :boolean, null: false, default: true
      add :unit, :integer, null: false, default: 1
      add :transport_config, :map, null: false, default: "{}"

      timestamps(type: :utc_datetime)
    end

    create index(:connections, [:device_id])
    create unique_index(:connections, [:base_topic], name: :connections_base_topic_index)

    flush()

    repo().insert_all(
      "connections",
      repo().all(
        from(d in "devices",
          select: %{
            device_id: d.id,
            protocol: d.protocol,
            base_topic: d.base_topic,
            active: d.active,
            unit: d.unit,
            transport_config: d.transport_config,
            inserted_at: d.inserted_at,
            updated_at: d.updated_at
          }
        )
      )
    )

    drop index(:devices, [:base_topic], name: :devices_base_topic_index)

    alter table(:devices) do
      remove :base_topic
      add :manufacturer, :string
      add :model_number, :string
    end
  end

  def down do
    # The old columns were never removed in `up`, so they are still present.
    alter table(:devices) do
      remove :manufacturer
      remove :model_number
      add :base_topic, :string, null: false
    end

    drop table(:connections)

    create unique_index(:devices, [:base_topic],
             name: :devices_base_topic_index,
             where: "base_topic IS NOT NULL"
           )
  end
end
