defmodule ModbusMqtt.Engine.RegisterCache do
  @moduledoc """
  An ETS-backed cache of raw Modbus register words.

  Each entry is keyed by `{device_id, register_type, address}` and stores
  the raw word value and the timestamp it was last written.

  Scanners write into this cache after each successful read.
  FieldInterpreters subscribe via PubSub for change notifications and
  read their dependency words from this cache to compute semantic values.
  """
  use GenServer

  @table :modbus_mqtt_register_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    table = Keyword.get(opts, :table, @table)

    case :ets.whereis(table) do
      :undefined -> :ets.new(table, [:named_table, :set, :public, read_concurrency: true])
      _ref -> :ok
    end

    {:ok, %{table: table}}
  end

  @doc """
  Writes a batch of raw words into the cache and publishes change notifications.

  `words` is a list of `{address, raw_word}` tuples from a contiguous scan.
  Returns the list of addresses whose values actually changed.
  """
  def put_words(device_id, register_type, words, opts \\ []) do
    table = Keyword.get(opts, :table, @table)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    pubsub = Keyword.get(opts, :pubsub, ModbusMqtt.PubSub)

    changed_addresses =
      for {address, raw_word} <- words, reduce: [] do
        acc ->
          key = {device_id, register_type, address}

          changed? =
            case :ets.lookup(table, key) do
              [{^key, ^raw_word, _ts}] -> false
              _ -> true
            end

          :ets.insert(table, {key, raw_word, now})

          if changed? do
            [address | acc]
          else
            acc
          end
      end

    if changed_addresses != [] do
      Phoenix.PubSub.broadcast(
        pubsub,
        register_topic(device_id, register_type),
        {:registers_updated, device_id, register_type, changed_addresses}
      )
    end

    changed_addresses
  end

  @doc """
  Reads a single raw word from the cache.
  Returns `{:ok, raw_word}` or `:error` if not cached.
  """
  # TODO: just delegate to get_words
  def get_word(device_id, register_type, address, opts \\ []) do
    case get_words(device_id, register_type, address, 1, opts) do
      {:ok, [raw_word]} -> {:ok, raw_word}
      _ -> :error
    end
  end

  @doc """
  Reads a contiguous range of raw words from the cache.
  Returns `{:ok, [word1, word2, ...]}` or `:error` if any address is missing.
  """
  def get_words(device_id, register_type, start_address, count, opts \\ []) do
    table = Keyword.get(opts, :table, @table)

    results =
      for offset <- 0..(count - 1) do
        key = {device_id, register_type, start_address + offset}

        case :ets.lookup(table, key) do
          [{^key, raw_word, _ts}] -> {:ok, raw_word}
          [] -> :error
        end
      end

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, word} -> word end)}
    else
      :error
    end
  end

  @doc "PubSub topic for register changes on a device + register type"
  def register_topic(device_id, register_type) do
    "register_cache:#{device_id}:#{register_type}"
  end
end
