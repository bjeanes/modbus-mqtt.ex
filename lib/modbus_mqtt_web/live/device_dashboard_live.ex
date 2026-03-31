defmodule ModbusMqttWeb.DeviceDashboardLive do
  use ModbusMqttWeb, :live_view

  alias ModbusMqtt.Devices
  alias ModbusMqtt.Engine.Hub

  @flash_ms 200
  @history_window_secs 5 * 60
  @default_history_points 11

  @impl true
  def mount(%{"id" => raw_id}, _session, socket) do
    socket = assign(socket, :current_scope, nil)

    case Integer.parse(raw_id) do
      {device_id, ""} ->
        mount_device(socket, device_id)

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid device id")
         |> push_navigate(to: ~p"/dashboards")}
    end
  end

  @impl true
  def handle_event("set_sort_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :sort_mode, parse_sort_mode(mode))}
  end

  @impl true
  def handle_info({:field_update, field_name, _value}, socket) do
    now = DateTime.utc_now()
    reading = Hub.get_field_reading(socket.assigns.device.id, field_name)

    socket =
      socket
      |> assign(:now, now)
      |> maybe_put_reading(field_name, reading)
      |> maybe_append_numeric_history(field_name, reading, now)
      |> track_field_update(field_name, now)
      |> put_flash_field(field_name)

    {:noreply, socket}
  end

  def handle_info({:clear_flash_field, field_name}, socket) do
    {:noreply, update(socket, :flashed_fields, &MapSet.delete(&1, field_name))}
  end

  def handle_info(:tick, socket) do
    now = DateTime.utc_now()

    {:noreply,
     socket
     |> assign(:now, now)
     |> prune_numeric_history(now)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="device-dashboard" class="space-y-6">
        <header class="space-y-3">
          <.link
            navigate={~p"/dashboards"}
            class="inline-flex items-center gap-2 text-sm text-primary"
          >
            <.icon name="hero-arrow-left" class="size-4" /> All dashboards
          </.link>

          <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="space-y-1">
              <h1 class="text-2xl font-semibold tracking-tight text-base-content">{@device.name}</h1>
              <p class="text-xs text-base-content/60">
                Device id {@device.id} | Topic {@device.base_topic || @device.id}
              </p>
            </div>

            <div class="rounded-lg bg-base-200 px-3 py-2 text-xs text-base-content/70">
              Updated {format_timestamp(@now)}
            </div>
          </div>

          <div
            id="sort-mode-toggle"
            phx-hook="PersistDeviceDashboardSort"
            data-sort-mode={sort_mode_value(@sort_mode)}
            class="flex flex-wrap items-center gap-2"
          >
            <span class="text-xs text-base-content/70">Sort mode:</span>
            <button
              id="sort-mode-alphabetical"
              type="button"
              phx-click="set_sort_mode"
              phx-value-mode="alphabetical"
              data-sort-mode="alphabetical"
              class={sort_mode_class(@sort_mode == :alphabetical)}
            >
              Alphabetical
            </button>
            <button
              id="sort-mode-recent"
              type="button"
              phx-click="set_sort_mode"
              phx-value-mode="recent"
              data-sort-mode="recent"
              class={sort_mode_class(@sort_mode == :recent)}
            >
              Most recent update
            </button>
            <button
              id="sort-mode-frequency"
              type="button"
              phx-click="set_sort_mode"
              phx-value-mode="frequency"
              data-sort-mode="frequency"
              class={sort_mode_class(@sort_mode == :frequency)}
            >
              Most frequently updated
            </button>
          </div>
        </header>

        <div class="overflow-x-auto rounded-xl border border-base-300 bg-base-100">
          <table id="register-table" class="table w-full text-sm">
            <thead>
              <tr>
                <th>Register</th>
                <th>Value</th>
                <th>Age</th>
                <th>Last update</th>
              </tr>
            </thead>
            <tbody>
              <%= for field <- sorted_fields(@fields, @sort_mode, @update_counts, @last_update_by_field) do %>
                <% reading = Map.get(@readings, field.name) %>
                <% flashing? = MapSet.member?(@flashed_fields, field.name) %>
                <tr
                  id={"field-#{field.id}"}
                  class={[
                    "transition-colors duration-700",
                    flashing? && "bg-amber-100/70"
                  ]}
                >
                  <td class="font-medium text-base-content">{field.name}</td>
                  <td class="font-mono text-xs sm:text-sm">
                    <div class="space-y-1">
                      <div>{formatted_value(reading)}</div>
                      <% series = sparkline_series_for(@numeric_history, field.name, @now) %>
                      <%= if numeric_field?(field, reading) and not is_nil(series) do %>
                        <% paths = sparkline_paths(series, 120, 28) %>
                        <svg
                          id={"sparkline-#{field.id}"}
                          viewBox="0 0 120 28"
                          class="h-7 w-[7.5rem] text-primary"
                          role="img"
                          aria-label={"Last 5 minutes trend for #{field.name}"}
                        >
                          <%= if paths.dashed do %>
                            <polyline
                              fill="none"
                              stroke="currentColor"
                              stroke-opacity="0.55"
                              stroke-width="2"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-dasharray="4 3"
                              points={paths.dashed}
                            />
                          <% end %>
                          <%= if paths.solid do %>
                            <polyline
                              fill="none"
                              stroke="currentColor"
                              stroke-width="2"
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              points={paths.solid}
                            />
                          <% end %>
                        </svg>
                      <% end %>
                    </div>
                  </td>
                  <td class="text-base-content/70">{age_label(reading, @now)}</td>
                  <td class="text-base-content/70">{last_update_label(reading)}</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp mount_device(socket, device_id) do
    case Devices.get_device(device_id) do
      %{active: true} = device ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{device.id}")
          :timer.send_interval(1_000, :tick)
        end

        fields =
          device.fields
          |> Enum.sort_by(&String.downcase(&1.name))

        now = DateTime.utc_now()
        readings = Hub.get_device_readings(device.id)

        {:ok,
         socket
         |> assign(:device, device)
         |> assign(:fields, fields)
         |> assign(:sort_mode, :alphabetical)
         |> assign(:update_counts, %{})
         |> assign(:last_update_by_field, %{})
         |> assign(:readings, readings)
         |> assign(:numeric_history, build_initial_numeric_history(fields, readings, now))
         |> assign(:flashed_fields, MapSet.new())
         |> assign(:now, now)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Device is missing or not active")
         |> push_navigate(to: ~p"/dashboards")}
    end
  end

  defp maybe_put_reading(socket, _field_name, nil), do: socket

  defp maybe_put_reading(socket, field_name, reading) do
    update(socket, :readings, &Map.put(&1, field_name, reading))
  end

  defp maybe_append_numeric_history(socket, _field_name, nil, _now), do: socket

  defp maybe_append_numeric_history(socket, field_name, reading, now) do
    case numeric_value(reading.value) do
      nil ->
        socket

      numeric ->
        update(socket, :numeric_history, fn history ->
          points = Map.get(history, field_name, [])
          new_points = [{now, numeric, :real} | points] |> prune_points(now)
          Map.put(history, field_name, new_points)
        end)
    end
  end

  defp build_initial_numeric_history(fields, readings, now) do
    Enum.reduce(fields, %{}, fn field, acc ->
      reading = Map.get(readings, field.name)

      if numeric_field?(field, reading) do
        points =
          case reading do
            %{value: value} ->
              case numeric_value(value) do
                nil -> default_points(now, 0.0)
                numeric -> [{now, numeric, :real} | default_points(now, 0.0)]
              end

            _ ->
              default_points(now, 0.0)
          end

        Map.put(acc, field.name, points)
      else
        acc
      end
    end)
  end

  defp default_points(now, value) do
    step = div(@history_window_secs, @default_history_points - 1)

    for offset <- 0..(@default_history_points - 1), reduce: [] do
      points ->
        age = @history_window_secs - offset * step
        ts = DateTime.add(now, -age, :second)
        [{ts, value, :default} | points]
    end
  end

  defp prune_numeric_history(socket, now) do
    update(socket, :numeric_history, fn history ->
      history
      |> Enum.map(fn {field_name, points} -> {field_name, prune_points(points, now)} end)
      |> Enum.reject(fn {_field_name, points} -> points == [] end)
      |> Map.new()
    end)
  end

  defp prune_points(points, now) do
    Enum.filter(points, fn {ts, _value, _kind} ->
      DateTime.diff(now, ts, :second) <= @history_window_secs
    end)
  end

  defp sparkline_series_for(history, field_name, now) do
    case history |> Map.get(field_name, []) |> prune_points(now) |> Enum.reverse() do
      [] ->
        nil

      points ->
        {default_points, real_points} =
          Enum.split_while(points, fn {_ts, _value, kind} -> kind == :default end)

        dashed_points =
          case {default_points, real_points} do
            {[], _} -> []
            {defaults, []} -> defaults
            {defaults, [first_real | _]} -> defaults ++ [first_real]
          end

        solid_points =
          case {default_points, real_points} do
            {_defaults, []} -> []
            {[], reals} -> reals
            {defaults, reals} -> [List.last(defaults) | reals]
          end

        %{all_points: points, dashed_points: dashed_points, solid_points: solid_points}
    end
  end

  defp sparkline_paths(
         %{all_points: all_points, dashed_points: dashed_points, solid_points: solid_points},
         width,
         height
       ) do
    pad = 2.0
    usable_width = width - 2 * pad
    usable_height = height - 2 * pad

    values = Enum.map(all_points, fn {_ts, value, _kind} -> value end)
    min_v = Enum.min(values)
    max_v = Enum.max(values)
    range_v = if max_v == min_v, do: 1.0, else: max_v - min_v

    times = Enum.map(all_points, fn {ts, _value, _kind} -> DateTime.to_unix(ts, :millisecond) end)
    min_t = Enum.min(times)
    max_t = Enum.max(times)
    range_t = max(max_t - min_t, 1)

    to_point = fn {ts, value, _kind} ->
      t = DateTime.to_unix(ts, :millisecond)
      x = pad + usable_width * (t - min_t) / range_t
      y = pad + usable_height * (max_v - value) / range_v
      "#{Float.round(x, 2)},#{Float.round(y, 2)}"
    end

    %{
      dashed: points_path(Enum.map(dashed_points, to_point)),
      solid: points_path(Enum.map(solid_points, to_point))
    }
  end

  defp points_path([]), do: nil
  defp points_path([single]), do: "#{single} #{single}"
  defp points_path(points), do: Enum.join(points, " ")

  defp numeric_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric_value(value) when is_integer(value), do: value * 1.0
  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(_value), do: nil

  defp numeric_field?(field, _reading) do
    field.data_type in [:int16, :uint16, :int32, :uint32, :float32] and
      field.value_semantics != :enum and
      is_nil(field.bit_mask)
  end

  defp sorted_fields(fields, :alphabetical, _update_counts, _last_update_by_field), do: fields

  defp sorted_fields(fields, :recent, _update_counts, last_update_by_field) do
    sort_indexes = alphabetical_indexes(fields)

    Enum.sort(fields, fn left, right ->
      left_updated = recency_score(left.name, last_update_by_field)
      right_updated = recency_score(right.name, last_update_by_field)

      cond do
        left_updated == right_updated ->
          Map.fetch!(sort_indexes, left.name) <= Map.fetch!(sort_indexes, right.name)

        true ->
          left_updated > right_updated
      end
    end)
  end

  defp sorted_fields(fields, :frequency, update_counts, last_update_by_field) do
    sort_indexes = alphabetical_indexes(fields)

    Enum.sort(fields, fn left, right ->
      left_count = Map.get(update_counts, left.name, 0)
      right_count = Map.get(update_counts, right.name, 0)

      cond do
        left_count == right_count ->
          left_updated = recency_score(left.name, last_update_by_field)
          right_updated = recency_score(right.name, last_update_by_field)

          cond do
            left_updated == right_updated ->
              Map.fetch!(sort_indexes, left.name) <= Map.fetch!(sort_indexes, right.name)

            true ->
              left_updated > right_updated
          end

        true ->
          left_count > right_count
      end
    end)
  end

  defp sorted_fields(fields, _unknown_mode, update_counts, last_update_by_field) do
    sorted_fields(fields, :alphabetical, update_counts, last_update_by_field)
  end

  defp alphabetical_indexes(fields) do
    fields
    |> Enum.with_index()
    |> Map.new(fn {field, idx} -> {field.name, idx} end)
  end

  defp recency_score(field_name, last_update_by_field) do
    case Map.get(last_update_by_field, field_name) do
      %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
      _ -> 0
    end
  end

  defp parse_sort_mode("alphabetical"), do: :alphabetical
  defp parse_sort_mode("chronological"), do: :alphabetical
  defp parse_sort_mode("recent"), do: :recent
  defp parse_sort_mode("frequency"), do: :frequency

  defp parse_sort_mode(_mode), do: :alphabetical

  defp track_field_update(socket, field_name, now) do
    socket
    |> update(:update_counts, &Map.update(&1, field_name, 1, fn count -> count + 1 end))
    |> update(:last_update_by_field, &Map.put(&1, field_name, now))
  end

  defp sort_mode_class(active?) do
    [
      "rounded-md border px-2 py-1 text-xs transition",
      if(active?,
        do: "border-primary bg-primary/15 text-primary",
        else: "border-base-300 bg-base-100 text-base-content/70"
      )
    ]
  end

  defp sort_mode_value(:alphabetical), do: "alphabetical"
  defp sort_mode_value(:recent), do: "recent"
  defp sort_mode_value(:frequency), do: "frequency"
  defp sort_mode_value(_), do: "alphabetical"

  defp put_flash_field(socket, field_name) do
    Process.send_after(self(), {:clear_flash_field, field_name}, @flash_ms)
    update(socket, :flashed_fields, &MapSet.put(&1, field_name))
  end

  defp formatted_value(nil), do: "--"
  defp formatted_value(reading), do: reading.formatted

  defp age_label(nil, _now), do: "never"

  defp age_label(%{updated_at: updated_at}, now) do
    secs = max(DateTime.diff(now, updated_at, :second), 0)

    cond do
      secs < 2 -> "just now"
      secs < 60 -> "#{secs}s"
      secs < 3600 -> "#{div(secs, 60)}m #{rem(secs, 60)}s"
      true -> "#{div(secs, 3600)}h #{div(rem(secs, 3600), 60)}m"
    end
  end

  defp last_update_label(nil), do: "--"

  defp last_update_label(%{updated_at: updated_at}) do
    format_timestamp(updated_at)
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  end
end
