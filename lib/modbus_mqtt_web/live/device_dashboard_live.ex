defmodule ModbusMqttWeb.DeviceDashboardLive do
  use ModbusMqttWeb, :live_view

  alias ModbusMqtt.Devices
  alias ModbusMqtt.Devices.Field
  alias ModbusMqttWeb.DeviceDashboard.FieldSorter
  alias ModbusMqtt.Engine.FieldSemantics
  alias ModbusMqtt.Engine.FieldWriter
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
  def handle_event("write_field", %{"field_id" => raw_field_id} = params, socket) do
    with {field_id, ""} <- Integer.parse(raw_field_id),
         field when not is_nil(field) <- Map.get(socket.assigns.fields_by_id, field_id),
         true <- Field.writable?(field),
         {:ok, value} <- extract_write_value(params),
         :ok <- FieldWriter.write(socket.assigns.device, field, value) do
      {:noreply, put_flash(socket, :info, "Queued write for #{field.name}")}
    else
      false ->
        {:noreply, put_flash(socket, :error, "Field is read-only")}

      nil ->
        {:noreply, put_flash(socket, :error, "Unknown field")}

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid field id")}

      {:error, :missing_value} ->
        {:noreply, put_flash(socket, :error, "Write value is required")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Write failed: #{inspect(reason)}")}
    end
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

  def handle_info({:clear_flash_field, field_name, timer_ref}, socket) do
    case Map.get(socket.assigns.flash_timers, field_name) do
      ^timer_ref ->
        {:noreply,
         socket
         |> update(:flashed_fields, &MapSet.delete(&1, field_name))
         |> update(:flash_timers, &Map.delete(&1, field_name))}

      _ ->
        # Ignore stale timer messages from superseded flashes.
        {:noreply, socket}
    end
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
    <Layouts.app flash={@flash} current_scope={@current_scope} max_width_class="max-w-[1800px]">
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

        <% {writable_fields, read_only_fields} =
          FieldSorter.partitioned(
            @fields,
            @sort_mode,
            @update_counts,
            @last_update_by_field
          ) %>

        <div class="grid gap-4 xl:grid-cols-2">
          <section id="writable-registers" class="space-y-2">
            <h2 class="px-1 text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Writable
            </h2>
            <div class="overflow-x-auto rounded-xl border border-base-300 bg-base-100">
              <table id="writable-register-table" class="table w-max min-w-full text-sm">
                <thead>
                  <tr>
                    <th>Register</th>
                    <th>Last update</th>
                    <th class="w-[22rem] min-w-[22rem]">Write</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for field <- writable_fields do %>
                    <% reading = Map.get(@readings, field.name) %>
                    <% flashing? = MapSet.member?(@flashed_fields, field.name) %>
                    <tr
                      id={"field-#{field.id}"}
                      data-flashing={to_string(flashing?)}
                      class={[
                        "transition-colors duration-700",
                        flashing? && "bg-amber-100/70"
                      ]}
                    >
                      <.field_identity_cell
                        field={field}
                        reading={reading}
                        numeric_history={@numeric_history}
                        now={@now}
                      />
                      <.field_update_cell reading={reading} now={@now} />
                      <td id={"write-td-#{field.id}"} phx-update="ignore" class="min-w-[22rem]">
                        <.form
                          for={%{}}
                          id={"write-field-#{field.id}"}
                          phx-submit="write_field"
                          class="mb-0"
                        >
                          <input type="hidden" name="field_id" value={field.id} />

                          <%= case write_input_kind(field) do %>
                            <% :boolean -> %>
                              <div class="flex items-center gap-2">
                                <.input
                                  type="checkbox"
                                  id={"write-value-#{field.id}"}
                                  name="value"
                                  checked={checkbox_checked?(reading)}
                                  class="checkbox checkbox-sm"
                                  label="Set"
                                />
                                <button type="submit" class="btn btn-xs btn-primary">Write</button>
                              </div>
                            <% :enum -> %>
                              <div class="flex items-center gap-2">
                                <.input
                                  type="select"
                                  id={"write-value-#{field.id}"}
                                  name="value"
                                  value={enum_selected_value(reading)}
                                  options={enum_options(field)}
                                  class="select select-sm w-48"
                                />
                                <button type="submit" class="btn btn-xs btn-primary">Write</button>
                              </div>
                            <% :number -> %>
                              <div class="flex items-center gap-2">
                                <.input
                                  type="number"
                                  id={"write-value-#{field.id}"}
                                  name="value"
                                  value={numeric_input_value(reading)}
                                  step={numeric_step(field)}
                                  class="input input-sm w-36"
                                />
                                <button type="submit" class="btn btn-xs btn-primary">Write</button>
                              </div>
                            <% :unsupported -> %>
                              <span class="text-xs text-base-content/60">Unsupported</span>
                          <% end %>
                        </.form>
                      </td>
                    </tr>
                  <% end %>

                  <%= if writable_fields == [] do %>
                    <tr>
                      <td colspan="3" class="text-center text-sm text-base-content/60">
                        No writable fields configured.
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>

          <section id="readonly-registers" class="space-y-2">
            <h2 class="px-1 text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Read-only
            </h2>
            <div class="overflow-x-auto rounded-xl border border-base-300 bg-base-100">
              <table id="readonly-register-table" class="table w-full text-sm">
                <thead>
                  <tr>
                    <th>Register</th>
                    <th>Last update</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for field <- read_only_fields do %>
                    <% reading = Map.get(@readings, field.name) %>
                    <% flashing? = MapSet.member?(@flashed_fields, field.name) %>
                    <tr
                      id={"field-#{field.id}"}
                      data-flashing={to_string(flashing?)}
                      class={[
                        "transition-colors duration-700",
                        flashing? && "bg-amber-100/70"
                      ]}
                    >
                      <.field_identity_cell
                        field={field}
                        reading={reading}
                        numeric_history={@numeric_history}
                        now={@now}
                      />
                      <.field_update_cell reading={reading} now={@now} />
                    </tr>
                  <% end %>

                  <%= if read_only_fields == [] do %>
                    <tr>
                      <td colspan="2" class="text-center text-sm text-base-content/60">
                        No read-only fields configured.
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </section>
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
         |> assign(:fields_by_id, Map.new(fields, &{&1.id, &1}))
         |> assign(:sort_mode, :alphabetical)
         |> assign(:update_counts, %{})
         |> assign(:last_update_by_field, %{})
         |> assign(:readings, readings)
         |> assign(:numeric_history, build_initial_numeric_history(fields, readings, now))
         |> assign(:flashed_fields, MapSet.new())
         |> assign(:flash_timers, %{})
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

  defp numeric_value(%Decimal{coef: special}) when special in [:NaN, :inf], do: nil
  defp numeric_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric_value(value) when is_integer(value), do: value * 1.0
  defp numeric_value(value) when is_float(value), do: value
  defp numeric_value(_value), do: nil

  defp numeric_field?(field, _reading) do
    field.data_type in [:int16, :uint16, :int32, :uint32, :float32] and
      field.value_semantics != :enum and
      is_nil(field.bit_mask)
  end

  attr :field, :map, required: true
  attr :reading, :map, default: nil
  attr :numeric_history, :map, required: true
  attr :now, :any, required: true

  defp field_identity_cell(assigns) do
    ~H"""
    <td class="align-top">
      <div class="space-y-1">
        <div class="font-medium text-base-content">{@field.name}</div>
        <div class="font-mono text-xs sm:text-sm">{formatted_value(@reading)}</div>
        <.field_sparkline
          :if={numeric_field?(@field, @reading)}
          field={@field}
          numeric_history={@numeric_history}
          now={@now}
        />
      </div>
    </td>
    """
  end

  attr :field, :map, required: true
  attr :numeric_history, :map, required: true
  attr :now, :any, required: true

  defp field_sparkline(assigns) do
    series = sparkline_series_for(assigns.numeric_history, assigns.field.name, assigns.now)
    assigns = assign(assigns, :series, series)

    ~H"""
    <%= if not is_nil(@series) do %>
      <% paths = sparkline_paths(@series, 120, 28) %>
      <svg
        id={"sparkline-#{@field.id}"}
        viewBox="0 0 120 28"
        class="h-7 w-[7.5rem] text-primary"
        role="img"
        aria-label={"Last 5 minutes trend for #{@field.name}"}
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
    """
  end

  attr :reading, :map, default: nil
  attr :now, :any, required: true

  defp field_update_cell(assigns) do
    ~H"""
    <td class="align-top text-base-content/70">
      <div class="space-y-1">
        <div>{last_update_label(@reading)}</div>
        <div class="text-xs">Age: {age_label(@reading, @now)}</div>
      </div>
    </td>
    """
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
    case Map.get(socket.assigns.flash_timers, field_name) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref, async: true, info: false)
    end

    clear_ref = make_ref()
    Process.send_after(self(), {:clear_flash_field, field_name, clear_ref}, @flash_ms)

    socket
    |> update(:flashed_fields, &MapSet.put(&1, field_name))
    |> update(:flash_timers, &Map.put(&1, field_name, clear_ref))
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

  defp extract_write_value(%{"value" => value}) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, :missing_value}
    else
      {:ok, trimmed}
    end
  end

  defp extract_write_value(%{"value" => value}), do: {:ok, value}
  defp extract_write_value(_params), do: {:error, :missing_value}

  defp write_input_kind(field) do
    cond do
      field.value_semantics == :enum -> :enum
      boolean_write_field?(field) -> :boolean
      numeric_write_field?(field) -> :number
      true -> :unsupported
    end
  end

  defp boolean_write_field?(field) do
    field.type == :coil or (field.data_type == :bool and is_nil(field.bit_mask))
  end

  defp numeric_write_field?(field) do
    field.value_semantics == :raw and
      field.data_type in [:int16, :uint16, :int32, :uint32, :float32] and
      is_nil(field.bit_mask)
  end

  defp checkbox_checked?(%{value: value}) when value in [true, 1], do: true
  defp checkbox_checked?(_reading), do: false

  defp enum_options(field) do
    field
    |> FieldSemantics.normalized_enum_map()
    |> Enum.sort_by(fn {code, _label} -> code end)
    |> Enum.map(fn {_code, label} -> {label, label} end)
  end

  defp enum_selected_value(%{value: value}) when is_binary(value), do: value
  defp enum_selected_value(_reading), do: nil

  defp numeric_input_value(%{value: %Decimal{coef: special}}) when special in [:NaN, :inf],
    do: "0"

  defp numeric_input_value(%{value: %Decimal{} = value}), do: Decimal.to_string(value, :normal)
  defp numeric_input_value(%{value: value}) when is_integer(value), do: Integer.to_string(value)
  defp numeric_input_value(%{value: value}) when is_float(value), do: Float.to_string(value)
  defp numeric_input_value(_reading), do: nil

  defp numeric_step(%{scale: scale}) when is_integer(scale) and scale < 0 do
    "0." <> String.duplicate("0", abs(scale) - 1) <> "1"
  end

  defp numeric_step(%{scale: scale}) when is_integer(scale) and scale > 0 do
    Integer.to_string(Integer.pow(10, scale))
  end

  defp numeric_step(_field), do: "1"
end
