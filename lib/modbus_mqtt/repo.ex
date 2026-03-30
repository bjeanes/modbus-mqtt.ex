defmodule ModbusMqtt.Repo do
  use Ecto.Repo,
    otp_app: :modbus_mqtt,
    adapter: Ecto.Adapters.SQLite3
end
