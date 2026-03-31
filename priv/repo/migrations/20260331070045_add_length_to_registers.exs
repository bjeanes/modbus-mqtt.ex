defmodule ModbusMqtt.Repo.Migrations.AddLengthToRegisters do
  use Ecto.Migration

  def change do
    alter table(:registers) do
      add :length, :integer, null: false
    end
  end
end
