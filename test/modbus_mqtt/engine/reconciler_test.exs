defmodule ModbusMqtt.Engine.ReconcilerTest do
  use ExUnit.Case, async: false

  alias ModbusMqtt.Engine.Reconciler
  alias ModbusMqtt.TestSupport.FakeDeviceSupervisor

  setup do
    :persistent_term.put({FakeDeviceSupervisor, :owner}, self())
    :persistent_term.put({FakeDeviceSupervisor, :pids}, %{})

    on_exit(fn ->
      :persistent_term.erase({FakeDeviceSupervisor, :owner})
      :persistent_term.erase({FakeDeviceSupervisor, :pids})
    end)

    :ok
  end

  test "stops engines for devices that become inactive" do
    owner = self()
    device_id = 1

    running_pid = spawn(fn -> Process.sleep(:infinity) end)
    :persistent_term.put({FakeDeviceSupervisor, :pids}, %{device_id => running_pid})

    updates = [
      [
        %{
          id: device_id,
          name: "A",
          protocol: :tcp,
          base_topic: "a",
          unit: 1,
          transport_config: %{},
          fields: []
        }
      ],
      []
    ]

    {:ok, updates_agent} = Agent.start_link(fn -> updates end)

    list_fun = fn ->
      Agent.get_and_update(updates_agent, fn
        [head | tail] -> {head, tail}
        [] -> {[], []}
      end)
    end

    start_fun = fn device ->
      send(owner, {:start_device, device.id})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    stop_fun = fn pid ->
      send(owner, {:stop_device, pid})
      :ok
    end

    {:ok, pid} =
      start_supervised(
        {Reconciler,
         [
           name: nil,
           reconcile_interval_ms: 30,
           list_active_devices_fun: list_fun,
           start_device_fun: start_fun,
           stop_device_fun: stop_fun,
           whereis_device_supervisor_fun: &FakeDeviceSupervisor.whereis/1
         ]}
      )

    assert_receive {:whereis, ^device_id}, 300
    assert_receive {:whereis, ^device_id}, 300
    assert_receive {:stop_device, ^running_pid}, 500

    GenServer.stop(pid)
    Agent.stop(updates_agent)
    Process.exit(running_pid, :kill)
  end

  test "restarts engines when field config changes" do
    owner = self()
    device_id = 2
    running_pid = spawn(fn -> Process.sleep(:infinity) end)

    initial = %{
      id: device_id,
      name: "B",
      protocol: :tcp,
      base_topic: "b",
      unit: 1,
      transport_config: %{},
      fields: [
        %{
          id: 10,
          name: "power",
          type: :holding_register,
          data_type: :uint16,
          address: 1,
          address_offset: 0,
          poll_interval_ms: 1000,
          scale: 0,
          swap_words: false,
          swap_bytes: false,
          value_semantics: :raw,
          enum_map: %{}
        }
      ]
    }

    changed = put_in(initial, [:fields, Access.at(0), :poll_interval_ms], 2000)

    updates = [initial, changed]
    {:ok, updates_agent} = Agent.start_link(fn -> updates end)

    list_fun = fn ->
      Agent.get_and_update(updates_agent, fn
        [head | tail] -> {[head], tail}
        [] -> {[], []}
      end)
    end

    start_fun = fn device ->
      send(owner, {:start_device, device.id})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    stop_fun = fn pid ->
      send(owner, {:stop_device, pid})
      :ok
    end

    whereis_fun = fn id ->
      send(owner, {:whereis, id})
      running_pid
    end

    {:ok, pid} =
      start_supervised(
        {Reconciler,
         [
           name: nil,
           reconcile_interval_ms: 30,
           list_active_devices_fun: list_fun,
           start_device_fun: start_fun,
           stop_device_fun: stop_fun,
           whereis_device_supervisor_fun: whereis_fun
         ]}
      )

    assert_receive {:whereis, ^device_id}, 300
    assert_receive {:whereis, ^device_id}, 500
    assert_receive {:stop_device, ^running_pid}, 500
    assert_receive {:start_device, ^device_id}, 500

    GenServer.stop(pid)
    Agent.stop(updates_agent)
    Process.exit(running_pid, :kill)
  end

  test "reconcile_now performs immediate pass" do
    owner = self()
    device_id = 3

    updates =
      Agent.start_link(fn ->
        [
          [],
          [
            %{
              id: device_id,
              name: "C",
              protocol: :tcp,
              base_topic: "c",
              unit: 1,
              transport_config: %{},
              fields: []
            }
          ]
        ]
      end)

    {:ok, updates_agent} = updates

    list_fun = fn ->
      Agent.get_and_update(updates_agent, fn
        [head | tail] -> {head, tail}
        [] -> {[], []}
      end)
    end

    start_fun = fn device ->
      send(owner, {:start_device, device.id})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    {:ok, pid} =
      start_supervised(
        {Reconciler,
         [
           name: nil,
           reconcile_interval_ms: :manual,
           list_active_devices_fun: list_fun,
           start_device_fun: start_fun,
           stop_device_fun: fn _pid -> :ok end,
           whereis_device_supervisor_fun: fn _id -> nil end
         ]}
      )

    refute_receive {:start_device, ^device_id}, 100
    Reconciler.reconcile_now(pid)
    assert_receive {:start_device, ^device_id}, 300

    GenServer.stop(pid)
    Agent.stop(updates_agent)
  end

  test "rapid reconcile_now calls are coalesced into a single pass" do
    owner = self()
    device_id = 4

    device = %{
      id: device_id,
      name: "D",
      protocol: :tcp,
      base_topic: "d",
      unit: 1,
      transport_config: %{},
      fields: []
    }

    {:ok, call_count} = Agent.start_link(fn -> 0 end)

    list_fun = fn ->
      Agent.update(call_count, &(&1 + 1))
      [device]
    end

    start_fun = fn dev ->
      send(owner, {:start_device, dev.id})
      {:ok, spawn(fn -> Process.sleep(:infinity) end)}
    end

    {:ok, pid} =
      start_supervised(
        {Reconciler,
         [
           name: nil,
           reconcile_interval_ms: :manual,
           list_active_devices_fun: list_fun,
           start_device_fun: start_fun,
           stop_device_fun: fn _pid -> :ok end,
           whereis_device_supervisor_fun: fn _id -> nil end
         ]}
      )

    # Drain the initial reconcile triggered from init
    assert_receive {:start_device, ^device_id}, 300
    initial_count = Agent.get(call_count, & &1)

    # Fire multiple rapid reconcile_now calls — should coalesce to one pass
    Reconciler.reconcile_now(pid)
    Reconciler.reconcile_now(pid)
    Reconciler.reconcile_now(pid)

    # Wait long enough for debounce to fire
    Process.sleep(200)

    final_count = Agent.get(call_count, & &1)

    assert final_count == initial_count + 1,
           "Expected exactly 1 extra reconcile pass, got #{final_count - initial_count}"

    GenServer.stop(pid)
    Agent.stop(call_count)
  end
end
