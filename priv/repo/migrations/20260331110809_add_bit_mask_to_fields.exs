defmodule ModbusMqtt.Repo.Migrations.AddBitMaskToFields do
  use Ecto.Migration

  def change do
    alter table(:fields) do
      add :bit_mask, :integer
    end
  end
end
