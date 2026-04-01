defmodule ModbusMqtt.Repo.Migrations.DropWritableFromFields do
  use Ecto.Migration

  def change do
    alter table(:fields) do
      remove :writable
    end
  end
end
