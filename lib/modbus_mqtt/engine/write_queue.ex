defmodule ModbusMqtt.Engine.WriteQueue do
  @moduledoc """
  Queues and retries writes per field.

  Behavior:
  - A new write for the same `{connection_id, field_name}` supersedes any pending one.
  - Pending writes are discarded when a fresh field value update arrives.
  - Retryable failures are retried with exponential backoff.
  - Emits write status events on `device:<id>` PubSub topics for LiveView feedback.
  """

  use GenServer

  require Logger

  alias ModbusMqtt.Engine.FieldWriter

  @default_retry_base_ms 500
  @default_max_retry_ms 5_000
  @default_max_attempts 5

  defstruct [
    :writer,
    :pubsub,
    :retry_base_ms,
    :max_retry_ms,
    :max_attempts,
    pending: %{},
    subscribed_connections: MapSet.new()
  ]

  @type status_state :: :pending | :retrying | :written | :failed | :discarded

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec write(map(), map(), term(), keyword()) :: :ok | {:error, :write_queue_not_running}
  def write(connection, field, value, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)

    case resolve_server_pid(server) do
      {:ok, _pid} ->
        GenServer.cast(server, {:queue_write, connection, field, value})
        :ok

      :error ->
        Logger.error("WriteQueue is not running; dropping write for #{field.name}")
        {:error, :write_queue_not_running}
    end
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{
       writer: Keyword.get(opts, :writer, FieldWriter),
       pubsub: Keyword.get(opts, :pubsub, ModbusMqtt.PubSub),
       retry_base_ms: Keyword.get(opts, :retry_base_ms, @default_retry_base_ms),
       max_retry_ms: Keyword.get(opts, :max_retry_ms, @default_max_retry_ms),
       max_attempts: Keyword.get(opts, :max_attempts, @default_max_attempts)
     }}
  end

  @impl true
  def handle_cast({:queue_write, connection, field, value}, state) do
    key = {connection.id, field.name}

    state =
      state
      |> ensure_connection_subscription(connection.id)
      |> discard_pending(key, :superseded)

    entry = %{connection: connection, field: field, value: value, attempt: 0, timer_ref: nil}
    broadcast_status(state, entry, :pending)
    send(self(), {:attempt_write, key})

    {:noreply, put_in(state.pending[key], entry)}
  end

  @impl true
  def handle_info({:attempt_write, key}, state) do
    case Map.get(state.pending, key) do
      nil ->
        {:noreply, state}

      entry ->
        {next_state, terminal?} = attempt_write(state, key, entry)

        if terminal? do
          {:noreply, maybe_unsubscribe_connection(next_state, entry.connection.id)}
        else
          {:noreply, next_state}
        end
    end
  end

  def handle_info({:field_value_changed, device_id, field_name, _value}, state) do
    key = {device_id, field_name}
    next_state = discard_pending(state, key, :value_changed)
    {:noreply, maybe_unsubscribe_connection(next_state, device_id)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp attempt_write(state, key, entry) do
    result = state.writer.write(entry.connection, entry.field, entry.value)

    case result do
      :ok ->
        broadcast_status(state, entry, :written)
        {pop_pending(state, key), true}

      {:error, reason} ->
        if retryable_write_error?(reason) and entry.attempt + 1 < state.max_attempts do
          attempt = entry.attempt + 1
          delay_ms = backoff_delay_ms(state, attempt)
          timer_ref = Process.send_after(self(), {:attempt_write, key}, delay_ms)

          next_entry = %{entry | attempt: attempt, timer_ref: timer_ref}

          broadcast_status(state, next_entry, :retrying, %{
            reason: reason,
            next_retry_ms: delay_ms
          })

          {put_in(state.pending[key], next_entry), false}
        else
          broadcast_status(state, entry, :failed, %{reason: reason})
          {pop_pending(state, key), true}
        end
    end
  end

  defp pop_pending(state, key) do
    update_in(state.pending, &Map.delete(&1, key))
  end

  defp discard_pending(state, key, reason) do
    case Map.get(state.pending, key) do
      nil ->
        state

      entry ->
        cancel_timer(entry.timer_ref)
        broadcast_status(state, entry, :discarded, %{reason: reason})
        pop_pending(state, key)
    end
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(timer_ref) do
    Process.cancel_timer(timer_ref)
    :ok
  end

  defp ensure_connection_subscription(state, connection_id) do
    if MapSet.member?(state.subscribed_connections, connection_id) do
      state
    else
      Phoenix.PubSub.subscribe(state.pubsub, device_topic(connection_id))
      update_in(state.subscribed_connections, &MapSet.put(&1, connection_id))
    end
  end

  defp maybe_unsubscribe_connection(state, connection_id) do
    pending_for_connection? =
      Enum.any?(state.pending, fn {{pending_connection_id, _field_name}, _entry} ->
        pending_connection_id == connection_id
      end)

    if pending_for_connection? or not MapSet.member?(state.subscribed_connections, connection_id) do
      state
    else
      Phoenix.PubSub.unsubscribe(state.pubsub, device_topic(connection_id))
      update_in(state.subscribed_connections, &MapSet.delete(&1, connection_id))
    end
  end

  defp device_topic(device_id), do: "device:#{device_id}"

  defp broadcast_status(state, entry, status, extra \\ %{}) do
    payload =
      Map.merge(
        %{
          state: status,
          attempt: entry.attempt,
          requested_value: entry.value
        },
        extra
      )

    Phoenix.PubSub.broadcast(
      state.pubsub,
      device_topic(entry.connection.id),
      {:field_write_status, entry.field.name, payload}
    )
  end

  defp backoff_delay_ms(state, attempt) do
    exponential = state.retry_base_ms * trunc(:math.pow(2, attempt - 1))
    min(exponential, state.max_retry_ms)
  end

  defp retryable_write_error?(:timeout), do: true
  defp retryable_write_error?(:not_connected), do: true
  defp retryable_write_error?(:device_not_running), do: true
  defp retryable_write_error?({:exit, _}), do: true
  defp retryable_write_error?({:modbus_error, _}), do: true
  defp retryable_write_error?(_), do: false

  defp resolve_server_pid(server) when is_pid(server) do
    if Process.alive?(server), do: {:ok, server}, else: :error
  end

  defp resolve_server_pid(server) when is_atom(server) do
    case Process.whereis(server) do
      nil -> :error
      pid -> {:ok, pid}
    end
  end

  defp resolve_server_pid(_server), do: :error
end
