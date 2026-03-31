defmodule ModbusMqtt.Repo.Migrations.AddValueSemanticsAndEnumMapToRegisters do
  use Ecto.Migration

  def change do
    alter table(:registers) do
      add :value_semantics, :string, null: false, default: "raw"
      add :enum_map, :map, null: false, default: %{}
    end
  end
end
