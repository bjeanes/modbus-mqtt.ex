defmodule ModbusMqttWeb.ConnectionDashboardIndexLive do
  use ModbusMqttWeb, :live_view

  alias ModbusMqtt.Connections
  alias ModbusMqtt.Mqtt.Status

  @impl true
  def mount(_params, _session, socket) do
    connections =
      Connections.list_active_connections_with_device_fields()
      |> Enum.sort_by(&String.downcase(&1.name))

    if connected?(socket) do
      Enum.each(connections, fn connection ->
        Phoenix.PubSub.subscribe(ModbusMqtt.PubSub, "device:#{connection.id}")
      end)
    end

    status_by_id =
      Map.new(connections, fn connection ->
        {connection.id, normalize_connection_status(Status.connection_status(connection))}
      end)

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:connections, connections)
     |> assign(:status_by_id, status_by_id)}
  end

  @impl true
  def handle_info({:connection_status_changed, connection_id, status}, socket) do
    {:noreply,
     update(
       socket,
       :status_by_id,
       &Map.put(&1, connection_id, normalize_connection_status(status))
     )}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-6">
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            Connection Dashboards
          </h1>
          <p class="text-sm text-base-content/70">
            Live dashboards for each active Modbus connection.
          </p>
        </div>

        <div id="connection-dashboard-list" class="grid gap-3 sm:grid-cols-2">
          <%= for connection <- @connections do %>
            <.link
              id={"connection-link-#{connection.id}"}
              navigate={~p"/connections/#{connection.id}/dashboard"}
              class="group rounded-xl border border-base-300 bg-base-100 p-4 transition hover:border-primary/50 hover:bg-base-200"
            >
              <div class="flex items-center justify-between gap-3">
                <h2 class="truncate text-base font-medium text-base-content group-hover:text-primary">
                  {connection.name}
                </h2>
                <span class="text-xs text-base-content/60">
                  {length(connection.fields)} registers
                </span>
              </div>
              <p class="mt-2 truncate text-xs text-base-content/60">
                Topic: {connection.base_topic || to_string(connection.id)}
              </p>
              <p class="mt-1 text-xs text-base-content/70">
                Status:
                <span class={status_badge_class(Map.get(@status_by_id, connection.id))}>
                  {Map.get(@status_by_id, connection.id)}
                </span>
              </p>
            </.link>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
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
end
