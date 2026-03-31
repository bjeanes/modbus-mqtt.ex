defmodule ModbusMqttWeb.DeviceDashboardLiveTest do
  use ModbusMqttWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ModbusMqtt.Devices.Device
  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Repo

  test "renders registers alphabetically with formatted value and update metadata", %{conn: conn} do
    device = device_fixture!("Boiler")
    field_zeta = field_fixture!(device, "zeta")
    _field_alpha = field_fixture!(device, "alpha")

    put_hub_reading!(device.id, field_zeta.name, 42, "42.0 C")

    {:ok, _view, html} = live(conn, ~p"/devices/#{device.id}/dashboard")

    assert String.contains?(html, "alpha")
    assert String.contains?(html, "zeta")
    assert String.contains?(html, "42.0 C")
    assert String.contains?(html, "just now")
    assert String.contains?(html, "UTC")
    assert byte_index!(html, "alpha") < byte_index!(html, "zeta")
  end

  test "flashes a row and updates formatted value when a field changes", %{conn: conn} do
    device = device_fixture!("Chiller")
    field = field_fixture!(device, "pressure")

    {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/dashboard")

    put_hub_reading!(device.id, field.name, 1, "1 bar")

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device.id}",
      {:field_update, field.name, 1}
    )

    wait_for(fn -> has_element?(view, "#field-#{field.id}", "1 bar") end)
    wait_for(fn -> String.contains?(render(view), "bg-amber-100/70") end)
  end

  test "renders sparkline for numeric values only", %{conn: conn} do
    device = device_fixture!("Compressor")
    numeric_field = field_fixture!(device, "amps")

    text_field =
      field_fixture!(device, "status", %{
        value_semantics: :enum,
        enum_map: %{"0" => "off", "1" => "on"}
      })

    bitmap_field =
      field_fixture!(device, "enabled", %{
        bit_mask: 1,
        data_type: :uint16,
        type: :holding_register
      })

    {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/dashboard")

    put_hub_reading!(device.id, numeric_field.name, 10, "10 A")

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device.id}",
      {:field_update, numeric_field.name, 10}
    )

    wait_for(fn -> has_element?(view, "#sparkline-#{numeric_field.id}") end)

    numeric_svg = sparkline_svg!(render(view), numeric_field.id)
    assert String.contains?(numeric_svg, "stroke-dasharray=\"4 3\"")
    assert count_occurrences(numeric_svg, "<polyline") == 2

    put_hub_reading!(device.id, text_field.name, "ok", "ok")

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device.id}",
      {:field_update, text_field.name, "ok"}
    )

    put_hub_reading!(device.id, bitmap_field.name, 1, "true")

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device.id}",
      {:field_update, bitmap_field.name, 1}
    )

    refute has_element?(view, "#sparkline-#{text_field.id}")
    refute has_element?(view, "#sparkline-#{bitmap_field.id}")
  end

  test "renders default zero sparkline for numeric fields on initial load", %{conn: conn} do
    device = device_fixture!("Pump")
    field = field_fixture!(device, "flow")

    {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/dashboard")

    assert has_element?(view, "#sparkline-#{field.id}")

    svg = sparkline_svg!(render(view), field.id)
    assert String.contains?(svg, "stroke-dasharray=\"4 3\"")
    assert count_occurrences(svg, "<polyline") == 1
  end

  test "supports alphabetical, recent, and frequency sort modes", %{conn: conn} do
    device = device_fixture!("Sorter")
    field_a = field_fixture!(device, "alpha")
    field_b = field_fixture!(device, "beta")
    field_c = field_fixture!(device, "gamma")

    {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}/dashboard")

    assert has_element?(
             view,
             "#sort-mode-toggle[phx-hook='PersistDeviceDashboardSort'][data-sort-mode='alphabetical']"
           )

    assert_row_order(render(view), [field_a.id, field_b.id, field_c.id])

    emit_update(device.id, field_a.name, 1, "1")
    Process.sleep(5)
    emit_update(device.id, field_b.name, 2, "2")
    Process.sleep(5)
    emit_update(device.id, field_c.name, 3, "3")
    Process.sleep(5)
    emit_update(device.id, field_c.name, 4, "4")

    render_click(element(view, "#sort-mode-recent"))
    assert has_element?(view, "#sort-mode-toggle[data-sort-mode='recent']")
    assert_row_order(render(view), [field_c.id, field_b.id, field_a.id])

    render_click(element(view, "#sort-mode-frequency"))
    assert has_element?(view, "#sort-mode-toggle[data-sort-mode='frequency']")
    assert_row_order(render(view), [field_c.id, field_b.id, field_a.id])

    render_click(element(view, "#sort-mode-alphabetical"))
    assert has_element?(view, "#sort-mode-toggle[data-sort-mode='alphabetical']")
    assert_row_order(render(view), [field_a.id, field_b.id, field_c.id])
  end

  defp device_fixture!(name) do
    %Device{}
    |> Device.changeset(%{
      name: name,
      base_topic: name |> String.downcase() |> String.replace(" ", "-")
    })
    |> Repo.insert!()
  end

  defp field_fixture!(device, name, attrs \\ %{}) do
    %Field{}
    |> Field.changeset(Map.merge(%{name: name, address: 10}, attrs))
    |> Ecto.Changeset.put_change(:device_id, device.id)
    |> Repo.insert!()
  end

  defp put_hub_reading!(device_id, field_name, value, formatted) do
    reading = %{bytes: [0, 1], decoded: value, value: value, formatted: formatted}
    :ets.insert(:modbus_mqtt_hub_cache, {{device_id, field_name}, reading, DateTime.utc_now()})
  end

  defp emit_update(device_id, field_name, value, formatted) do
    put_hub_reading!(device_id, field_name, value, formatted)

    Phoenix.PubSub.broadcast!(
      ModbusMqtt.PubSub,
      "device:#{device_id}",
      {:field_update, field_name, value}
    )
  end

  defp assert_row_order(html, field_ids) do
    indices = Enum.map(field_ids, fn id -> byte_index!(html, "id=\"field-#{id}\"") end)
    assert indices == Enum.sort(indices)
  end

  defp byte_index!(string, pattern) do
    case :binary.match(string, pattern) do
      {index, _length} -> index
      :nomatch -> flunk("expected #{inspect(pattern)} in html")
    end
  end

  defp sparkline_svg!(html, field_id) do
    regex = ~r/<svg[^>]*id="sparkline-#{field_id}"[\s\S]*?<\/svg>/

    case Regex.run(regex, html) do
      [svg] -> svg
      _ -> flunk("expected sparkline svg for field #{field_id}")
    end
  end

  defp count_occurrences(string, token) do
    string
    |> String.split(token)
    |> length()
    |> Kernel.-(1)
  end

  defp wait_for(fun, attempts \\ 30)

  defp wait_for(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_for(fun, attempts - 1)
    end
  end

  defp wait_for(_fun, 0) do
    flunk("condition was not met in time")
  end
end
