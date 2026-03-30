defmodule ModbusMqtt.Repo.Migrations.CreateRegisters do
  use Ecto.Migration

  def change do
    create table(:registers) do
      add :name, :string, null: false
      add :type, :string, null: false, default: "holding_register"
      add :data_type, :string, null: false, default: "uint16"
      add :address, :integer, null: false
      add :address_offset, :integer, null: false, default: 0
      add :poll_interval_ms, :integer, null: false, default: 5000
      add :writable, :boolean, default: false, null: false
      add :scale, :integer, null: false, default: 0
      add :swap_words, :boolean, default: false, null: false
      add :swap_bytes, :boolean, default: false, null: false
      add :device_id, references(:devices, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:registers, [:device_id])
  end
end
