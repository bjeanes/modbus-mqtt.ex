defmodule ModbusMqttWeb.PageController do
  use ModbusMqttWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
