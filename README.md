# Modbus MQTT Bridge

Modbus MQTT Bridge polls Modbus devices, keeps the latest interpreted field state in memory, publishes telemetry to MQTT, exposes LiveView dashboards, and accepts controlled writes for writable fields.

The current project is aimed at a single-site or home-lab deployment, with Home Assistant integration as a primary use case.

## What it does today

- Stores device and field definitions in SQLite through Ecto.
- Starts one supervised runtime tree per active device and continuously reconciles that runtime state with the database.
- Connects to Modbus TCP and RTU devices through the bundled adapter.
- Polls fields at per-field intervals, including contiguous scan coalescing under the hood.
- Decodes and scales `int16`, `uint16`, `int32`, `uint32`, `float32`, `string`, and `bool` values.
- Supports enum semantics, bit-mask extraction, byte and word swapping, and engineering units for numeric raw fields.
- Publishes changed values to MQTT and suppresses duplicate publishes when the value and bytes are unchanged.
- Publishes retained bridge and device status topics.
- Publishes Home Assistant MQTT discovery payloads for active fields.
- Provides LiveView dashboards at `/dashboards` and `/devices/:id/dashboard` with live updates, sparklines, recency indicators, sort modes, and write controls for writable fields.
- Accepts writes from the dashboard UI and MQTT `/set` topics, with retry and backoff for retryable failures.

## Current scope

This is not a cloud service or multi-tenant platform. It is a local bridge for reliable device telemetry and selective control.

The runtime already includes write support, but only for writable Modbus field types:

- `:coil`
- `:holding_register`

The UI and MQTT write path currently support:

- Boolean writes
- Numeric writes
- Enum-backed writes

## Architecture

1. `ModbusMqtt.Engine.Reconciler` keeps active connection trees aligned with the database.
2. `ModbusMqtt.Engine.Supervisor` runs one `ConnectionSupervisor` per active connection.
3. Each connection tree manages a Modbus connection process, scan processes, field interpretation, and write coordination.
4. `ModbusMqtt.Engine.RegisterCache` stores raw words in ETS.
5. `ModbusMqtt.Engine.Hub` stores the latest interpreted readings, broadcasts updates internally, and publishes MQTT telemetry.
6. `ModbusMqtt.Mqtt.Status` publishes retained bridge and connection availability metadata.
7. `ModbusMqtt.Mqtt.HomeAssistant` publishes Home Assistant discovery configs for active fields.

## MQTT contract

The default base topic is `modbus_mqtt`. You can change it via `MQTT_URL`.

For each device, the MQTT device segment is:

- `device.base_topic` when present
- otherwise the numeric device ID

Topics:

- Value topic: `<base>/<device>/<field>`
- Detail topic: `<base>/<device>/<field>/detail`
- Write topic: `<base>/<device>/<field>/set`
- Bridge status: `<base>/status`
- Device status: `<base>/devices/<device>/status`
- Device last error: `<base>/devices/<device>/last_error`

The plain value topic publishes the field's formatted value.

The detail topic publishes JSON shaped like:

```json
{
  "bytes": [0, 1],
  "decoded": 1,
  "formatted": "0.1 kWh",
  "value": 0.1
}
```

MQTT writes are accepted on `/set` topics. Payloads may be plain text or JSON values. The inbound value is interpreted according to the field definition before being encoded for Modbus.

## Home Assistant

Home Assistant discovery is already published for active fields.

- Discovery prefix defaults to `homeassistant`
- Discovery is republished when the MQTT connection comes up
- Discovery is also republished when `homeassistant/status` receives `online`

Component type is derived from field capabilities:

- Read-only boolean fields become `binary_sensor`
- Read-only non-boolean fields become `sensor`
- Writable boolean fields become `switch`
- Writable enum fields become `select`
- Writable numeric fields become `number`

## Web UI

The main project UI is the device dashboard index at `http://localhost:4000/dashboards`.

Current dashboard behavior includes:

- Live value updates over PubSub
- Last-update timestamps and age labels
- Numeric sparklines over a rolling five-minute window
- Sort modes for alphabetical, most recent update, and most frequent update
- Separate writable and read-only tables
- Inline write controls with pending, retrying, failed, discarded, and written feedback

The `/` route still serves the default Phoenix landing page.

## Supported transport state

The bundled client supports:

- Modbus TCP
- Modbus RTU

The device schema includes a `:custom` protocol value for future extension, but there is no bundled custom transport adapter yet.

## Run locally

Prerequisites:

- Elixir and Erlang versions compatible with `mix.exs`
- A reachable MQTT broker, defaulting to `localhost:1883`

Setup and run:

1. Install dependencies, create the database, migrate, seed, and build assets:

   ```bash
   mix setup
   ```

2. Start the Phoenix app:

   ```bash
   mix phx.server
   ```

   or:

   ```bash
   iex -S mix phx.server
   ```

3. Open:

- `http://localhost:4000/dashboards`
- `http://localhost:4000/dev/dashboard` in development for LiveDashboard

## Configuration

Runtime configuration is primarily driven by environment variables in `config/runtime.exs`.

- `MQTT_URL`
  Example: `mqtt://user:pass@broker.local:1883/modbus_mqtt`
- `MQTT_CLIENT_ID`
  Optional explicit MQTT client ID
- `DATABASE_PATH`
  Required in production
- `SECRET_KEY_BASE`
  Required in production
- `PHX_SERVER`
  Enables the web server in releases
- `PHX_HOST`
  Production host, defaults to `example.com`
- `PORT`
  Production HTTP port, defaults to `4000`

The seed script at `priv/repo/seeds.exs` loads a sample Sungrow inverter device with a mix of telemetry and writable fields.

## Development checks

Run the project quality gate before finishing changes:

```bash
mix precommit
```
