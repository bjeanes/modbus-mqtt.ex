defmodule ModbusMqttWeb.ConnectionDashboardLive do
  use ModbusMqttWeb, :live_view

  alias ModbusMqtt.Connections
  alias ModbusMqtt.Devices.Field
  alias ModbusMqtt.Mqtt.Status
  alias ModbusMqttWeb.DeviceDashboard.FieldSorter
  alias ModbusMqtt.Engine.FieldSemantics
  alias ModbusMqtt.Engine.Hub
  alias ModbusMqtt.Engine.WriteQueue

  @flash_ms 200
  @history_window_secs 5 * 60
  @default_history_points 11

  @impl true
  def mount(%{"id" => raw_id}, _session, socket) do
    socket = assign(socket, :current_scope, nil)

    case Integer.parse(raw_id) do
      {connection_id, ""} ->
        mount_connection(socket, connection_id)

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Invalid connection id")
         |> push_navigate(to: ~p"/dashboards")}
    end
  end

  @impl true
  def handle_event("set_sort_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :sort_mode, parse_sort_mode(mode))}
  end

  @impl true
  def handle_event("stage_write", %{"field_id" => raw_field_id} = params, socket) do
    with {field_id, ""} <- Integer.parse(raw_field_id),
         field when not is_nil(field) <- Map.get(socket.assigns.fields_by_id, field_id),
         true <- Field.writable?(field),
         {:ok, staged_value} <- staged_value_from_params(field, params) do
      reading = Map.get(socket.assigns.readings, field.name)
      current_input = current_input_value(field, reading)

      staged_writes =
        if is_nil(staged_value) or staged_value == current_input do
          Map.delete(socket.assigns.staged_writes, field.name)
        else
          Map.put(socket.assigns.staged_writes, field.name, staged_value)
        end

      {:noreply, assign(socket, :staged_writes, staged_writes)}
    else
      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("write_field", %{"field_id" => raw_field_id} = params, socket) do
    with {field_id, ""} <- Integer.parse(raw_field_id),
         field when not is_nil(field) <- Map.get(socket.assigns.fields_by_id, field_id),
         true <- Field.writable?(field),
         {:ok, value} <- extract_write_value(params),
         :ok <- WriteQueue.write(socket.assigns.connection, field, value) do
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
    reading = Hub.get_field_reading(socket.assigns.connection.id, field_name)

    socket =
      socket
      |> assign(:now, now)
      |> maybe_put_reading(field_name, reading)
      |> maybe_append_numeric_history(field_name, reading, now)
      |> track_field_update(field_name, now)
      |> maybe_clear_staged_write(field_name, reading)
      |> update(:write_statuses, &Map.delete(&1, field_name))
      |> put_flash_field(field_name)

    {:noreply, socket}
  end

  def handle_info({:field_write_status, field_name, status}, socket) do
    socket =
      socket
      |> update(:write_statuses, &Map.put(&1, field_name, status))
      |> maybe_clear_staged_write_on_confirmed(field_name, status)

    {:noreply, socket}
  end

  def handle_info({:field_value_changed, _connection_id, field_name, _value}, socket) do
    # Value-changed events are primarily consumed by WriteQueue to cancel stale retries.
    # LiveView already updates readings via {:field_update, ...}, so we only clear pending
    # write state here to avoid stale status badges and prevent clause errors.
    {:noreply, update(socket, :write_statuses, &Map.delete(&1, field_name))}
  end

  def handle_info({:connection_status_changed, connection_id, status}, socket) do
    if connection_id == socket.assigns.connection.id do
      {:noreply, assign(socket, :connection_status, normalize_connection_status(status))}
    else
      {:noreply, socket}
    end
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
      <section id="connection-dashboard" class="space-y-6">
        <header class="space-y-3">
          <.link
            navigate={~p"/dashboards"}
            class="inline-flex items-center gap-2 text-sm text-primary"
          >
            <.icon name="hero-arrow-left" class="size-4" /> All dashboards
          </.link>

          <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="space-y-1">
              <h1 class="text-2xl font-semibold tracking-tight text-base-content">
                {@connection.name}
              </h1>
              <p class="text-xs text-base-content/60">
                Connection id {@connection.id} | Topic {@connection.base_topic || @connection.id}
              </p>
              <p class="text-xs text-base-content/60">
                Status:
                <span class={status_badge_class(@connection_status)}>{@connection_status}</span>
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
                    <% staged = Map.get(@staged_writes, field.name) %>
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
                      <td id={"write-td-#{field.id}"} class="min-w-[22rem]">
                        <.form
                          for={%{}}
                          id={"write-field-#{field.id}"}
                          phx-change="stage_write"
                          phx-submit="write_field"
                          class="mb-0"
                        >
                          <input type="hidden" name="field_id" value={field.id} />

                          <div id={"write-control-#{field.id}"}>
                            <%= case write_input_kind(field) do %>
                              <% :boolean -> %>
                                <div class="flex items-center gap-2">
                                  <.input
                                    type="checkbox"
                                    id={"write-value-#{field.id}"}
                                    name="value"
                                    checked={checkbox_checked_with_stage(staged, reading)}
                                    class="checkbox checkbox-sm"
                                    label="Set"
                                  />
                                  <button
                                    :if={not is_nil(staged)}
                                    type="submit"
                                    class="btn btn-xs btn-primary"
                                  >
                                    Write
                                  </button>
                                </div>
                              <% :enum -> %>
                                <div class="flex items-center gap-2">
                                  <.input
                                    type="select"
                                    id={"write-value-#{field.id}"}
                                    name="value"
                                    value={staged || enum_selected_value(reading)}
                                    options={enum_options(field)}
                                    class="select select-sm w-48"
                                  />
                                  <button
                                    :if={not is_nil(staged)}
                                    type="submit"
                                    class="btn btn-xs btn-primary"
                                  >
                                    Write
                                  </button>
                                </div>
                              <% :number -> %>
                                <div class="flex items-center gap-2">
                                  <.input
                                    type="number"
                                    id={"write-value-#{field.id}"}
                                    name="value"
                                    value={staged || numeric_input_value(reading)}
                                    step={numeric_step(field)}
                                    class="input input-sm w-36"
                                  />
                                  <button
                                    :if={not is_nil(staged)}
                                    type="submit"
                                    class="btn btn-xs btn-primary"
                                  >
                                    Write
                                  </button>
                                </div>
                              <% :unsupported -> %>
                                <span class="text-xs text-base-content/60">Unsupported</span>
                            <% end %>
                          </div>

                          <.write_status field={field} status={Map.get(@write_statuses, field.name)} />
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

  defp mount_connection(socket, connection_id) do
    case Connections.get_connection_with_device_fields(connection_id) do
      %{active: true} = connection ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{connection.id}")
          :timer.send_interval(1_000, :tick)
        end

        fields =
          connection.fields
          |> Enum.sort_by(&String.downcase(&1.name))

        now = DateTime.utc_now()
        readings = Hub.get_device_readings(connection.id)

        {:ok,
         socket
         |> assign(:connection, connection)
         |> assign(:fields, fields)
         |> assign(:fields_by_id, Map.new(fields, &{&1.id, &1}))
         |> assign(:fields_by_name, Map.new(fields, &{&1.name, &1}))
         |> assign(:sort_mode, :alphabetical)
         |> assign(:update_counts, %{})
         |> assign(:last_update_by_field, %{})
         |> assign(:readings, readings)
         |> assign(:numeric_history, build_initial_numeric_history(fields, readings, now))
         |> assign(:flashed_fields, MapSet.new())
         |> assign(:flash_timers, %{})
         |> assign(:staged_writes, %{})
         |> assign(:write_statuses, %{})
         |> assign(
           :connection_status,
           normalize_connection_status(Status.connection_status(connection))
         )
         |> assign(:now, now)}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Connection is missing or inactive")
         |> push_navigate(to: ~p"/dashboards")}
    end
  end

  defp normalize_connection_status(nil), do: "unknown"
  defp normalize_connection_status(status) when is_binary(status), do: status
  defp normalize_connection_status(status), do: to_string(status)

  defp status_badge_class(status) do
    [
      "ml-1 inline-flex rounded-full border px-2 py-0.5 font-medium",
      case status do
        "online" -> "border-emerald-300 bg-emerald-100 text-emerald-800"
        "connecting" -> "border-amber-300 bg-amber-100 text-amber-800"
        "retrying_connection" -> "border-amber-300 bg-amber-100 text-amber-800"
        "connection_failed" -> "border-rose-300 bg-rose-100 text-rose-800"
        "offline" -> "border-slate-300 bg-slate-100 text-slate-700"
        _ -> "border-base-300 bg-base-200 text-base-content/70"
      end
    ]
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
          points = maybe_backfill_default_points(points, numeric)
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
                numeric -> [{now, numeric, :real} | default_points(now, numeric)]
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

  defp maybe_backfill_default_points(points, first_value) do
    if Enum.any?(points, fn {_ts, _value, kind} -> kind == :real end) do
      points
    else
      Enum.map(points, fn {ts, _value, kind} -> {ts, first_value, kind} end)
    end
  end

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
          reading={@reading}
          numeric_history={@numeric_history}
          now={@now}
        />
      </div>
    </td>
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

  attr :field, :map, required: true
  attr :status, :map, default: nil

  defp write_status(%{status: nil} = assigns) do
    ~H"""
    """
  end

  defp write_status(assigns) do
    ~H"""
    <p id={"write-status-#{@field.id}"} class="mt-1 text-xs text-base-content/70">
      <%= case @status.state do %>
        <% :pending -> %>
          Pending write...
        <% :retrying -> %>
          Retrying (attempt {@status.attempt + 1})
        <% :failed -> %>
          Write failed: {inspect(@status.reason)}
        <% :discarded -> %>
          Pending write discarded
        <% :written -> %>
          Write accepted by connection
      <% end %>
    </p>
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

  defp staged_value_from_params(field, params) do
    case write_input_kind(field) do
      :boolean ->
        value = if truthy_checkbox?(Map.get(params, "value")), do: "true", else: "false"
        {:ok, value}

      :enum ->
        {:ok, normalize_string_param(Map.get(params, "value"))}

      :number ->
        {:ok, normalize_string_param(Map.get(params, "value"))}

      :unsupported ->
        {:error, :unsupported}
    end
  end

  defp normalize_string_param(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string_param(_), do: nil

  defp current_input_value(field, reading) do
    case write_input_kind(field) do
      :boolean -> if(checkbox_checked?(reading), do: "true", else: "false")
      :enum -> enum_selected_value(reading)
      :number -> numeric_input_value(reading)
      :unsupported -> nil
    end
  end

  defp maybe_clear_staged_write(socket, field_name, reading) do
    case Map.fetch(socket.assigns.staged_writes, field_name) do
      :error ->
        socket

      {:ok, staged_value} ->
        field = Map.get(socket.assigns.fields_by_name, field_name)
        current = current_input_value(field, reading)

        if staged_value == current do
          update(socket, :staged_writes, &Map.delete(&1, field_name))
        else
          socket
        end
    end
  end

  defp maybe_clear_staged_write_on_confirmed(socket, field_name, %{state: :written}) do
    update(socket, :staged_writes, &Map.delete(&1, field_name))
  end

  defp maybe_clear_staged_write_on_confirmed(socket, _field_name, _status), do: socket

  defp write_input_kind(field) do
    cond do
      boolean_write_field?(field) -> :boolean
      field.value_semantics == :enum -> :enum
      numeric_write_field?(field) -> :number
      true -> :unsupported
    end
  end

  defp boolean_write_field?(field) do
    field.type == :coil or
      (field.data_type == :bool and is_nil(field.bit_mask)) or
      Field.enum_boolean?(field)
  end

  defp numeric_write_field?(field) do
    field.value_semantics == :raw and
      field.data_type in [:int16, :uint16, :int32, :uint32, :float32] and
      is_nil(field.bit_mask)
  end

  defp checkbox_checked?(%{value: value}) when value in [true, 1], do: true
  defp checkbox_checked?(_reading), do: false

  defp checkbox_checked_with_stage("true", _reading), do: true
  defp checkbox_checked_with_stage("false", _reading), do: false
  defp checkbox_checked_with_stage(_staged, reading), do: checkbox_checked?(reading)

  defp truthy_checkbox?(value) when value in [true, 1, "1", "true", "on"], do: true
  defp truthy_checkbox?(_), do: false

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
