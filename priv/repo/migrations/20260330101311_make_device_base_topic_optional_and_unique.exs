defmodule ModbusMqtt.Repo.Migrations.MakeDeviceBaseTopicOptionalAndUnique do
  use Ecto.Migration

  def change do
    create unique_index(:devices, [:base_topic])
  end
end
