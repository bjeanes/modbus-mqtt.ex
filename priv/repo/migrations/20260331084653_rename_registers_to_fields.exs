defmodule ModbusMqtt.Repo.Migrations.RenameRegistersToFields do
  use Ecto.Migration

  def change do
    rename table(:registers), to: table(:fields)

    # Rename the index to match the new table name
    drop index(:fields, [:device_id], name: :registers_device_id_index)
    create index(:fields, [:device_id])
  end
end
