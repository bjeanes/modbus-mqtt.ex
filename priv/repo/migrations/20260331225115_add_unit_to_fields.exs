defmodule ModbusMqtt.Repo.Migrations.AddUnitToFields do
  use Ecto.Migration

  def change do
    alter table(:fields) do
      add :unit, :string
    end
  end
end
