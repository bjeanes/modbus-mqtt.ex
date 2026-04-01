defmodule ModbusMqttWeb.DeviceDashboard.FieldSorter do
  @moduledoc """
  Sorting and partitioning helpers for dashboard fields.
  """

  alias ModbusMqtt.Devices.Field

  def sorted(fields, :alphabetical, _update_counts, _last_update_by_field), do: fields

  def sorted(fields, :recent, _update_counts, last_update_by_field) do
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

  def sorted(fields, :frequency, update_counts, last_update_by_field) do
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

  def sorted(fields, _unknown_mode, update_counts, last_update_by_field) do
    sorted(fields, :alphabetical, update_counts, last_update_by_field)
  end

  def partitioned(fields, sort_mode, update_counts, last_update_by_field) do
    fields
    |> sorted(sort_mode, update_counts, last_update_by_field)
    |> Enum.split_with(&Field.writable?/1)
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
end
