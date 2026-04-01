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
      client_id: client_id(),
      server: server_opt,
      handler: {ModbusMqtt.Mqtt.Handler, []},
      subscriptions: [
        {ModbusMqtt.Mqtt.Topics.device_value_set_topic_filter(), 0},
        {ModbusMqtt.Mqtt.Topics.home_assistant_status_topic(), 0}
      ],
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
    Tortoise311.publish(client_id(), topic, normalized_payload, opts)
  end

  defp client_id do
    Application.fetch_env!(:modbus_mqtt, :mqtt)[:client_id] || default_client_id()
  end

  defp default_client_id do
    {:ok, hostname} = :inet.gethostname()
    "modbus_mqtt@#{hostname}"
  end

  defp bridge_last_will do
    %Publish{topic: Status.bridge_status_topic(), payload: "offline", retain: true, qos: 0}
  end
end
