defmodule ModbusMqtt.Mqtt.Supervisor do
  use Supervisor

  alias ModbusMqtt.Mqtt.Status
  alias Tortoise311.Package.Publish

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    config = Application.fetch_env!(:modbus_mqtt, :mqtt)

    server_opt = {Tortoise311.Transport.Tcp, host: config[:host], port: config[:port]}

    opts = [
      client_id: "modbus_mqtt_client",
      server: server_opt,
      handler: {ModbusMqtt.Mqtt.Handler, []},
      will: bridge_last_will()
    ]

    opts =
      if config[:username] && config[:password] do
        Keyword.merge(opts, user_name: config[:username], password: config[:password])
      else
        opts
      end

    children = [
      {Tortoise311.Connection, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc "Helper to publish a payload to the broker"
  def publish(topic, payload, opts \\ []) do
    normalized_payload = if is_nil(payload), do: nil, else: to_string(payload)
    Tortoise311.publish("modbus_mqtt_client", topic, normalized_payload, opts)
  end

  defp bridge_last_will do
    %Publish{topic: Status.bridge_status_topic(), payload: "offline", retain: true, qos: 0}
  end
end
