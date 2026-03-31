defmodule ModbusMqttWeb.DeviceDashboardIndexLive do
  use ModbusMqttWeb, :live_view

  alias ModbusMqtt.Devices

  @impl true
  def mount(_params, _session, socket) do
    devices =
      Devices.list_active_devices_with_fields()
      |> Enum.sort_by(&String.downcase(&1.name))

    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:devices, devices)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="space-y-6">
        <div class="space-y-2">
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">Device Dashboards</h1>
          <p class="text-sm text-base-content/70">
            Live dashboards for each monitored device.
          </p>
        </div>

        <div id="device-dashboard-list" class="grid gap-3 sm:grid-cols-2">
          <%= for device <- @devices do %>
            <.link
              id={"device-link-#{device.id}"}
              navigate={~p"/devices/#{device.id}/dashboard"}
              class="group rounded-xl border border-base-300 bg-base-100 p-4 transition hover:border-primary/50 hover:bg-base-200"
            >
              <div class="flex items-center justify-between gap-3">
                <h2 class="truncate text-base font-medium text-base-content group-hover:text-primary">
                  {device.name}
                </h2>
                <span class="text-xs text-base-content/60">{length(device.fields)} registers</span>
              </div>
              <p class="mt-2 truncate text-xs text-base-content/60">
                Topic: {device.base_topic || to_string(device.id)}
              </p>
            </.link>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
