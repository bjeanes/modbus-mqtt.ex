defmodule ModbusMqttWeb.PageController do
  use ModbusMqttWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/dashboards")
  end
end
