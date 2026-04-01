defmodule ModbusMqttWeb.DeviceDashboardSparklineComponents do
  @moduledoc """
  Function components and helpers for device dashboard sparklines.
  """

  use Phoenix.Component

  @history_window_secs 5 * 60

  attr :field, :map, required: true
  attr :numeric_history, :map, required: true
  attr :now, :any, required: true

  def field_sparkline(assigns) do
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

  defp prune_points(points, now) do
    Enum.filter(points, fn {ts, _value, _kind} ->
      DateTime.diff(now, ts, :second) <= @history_window_secs
    end)
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
end
