defmodule ModbusMqttWeb.PageControllerTest do
  use ModbusMqttWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/dashboards"
  end
end
