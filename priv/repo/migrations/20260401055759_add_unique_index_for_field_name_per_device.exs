defmodule ModbusMqtt.Repo.Migrations.AddUniqueIndexForFieldNamePerDevice do
  use Ecto.Migration

  def change do
    create unique_index(:fields, [:device_id, :name], name: :fields_device_id_name_index)
  end
end
