# Modbus MQTT Bridge

Modbus MQTT Bridge polls Modbus device registers and publishes fresh values to MQTT.
Its immediate focus is single-site home automation integration (starting with a Sungrow inverter), with a read-first roadmap that prioritizes telemetry quality, reliability, and Home Assistant integration before any write features.

## Project purpose

Expose Modbus device state over MQTT in a way that is:

- Near real-time for frequently changing values
- Robust and self-healing when devices or network links are unstable
- Extensible to custom transports (not only plain Modbus TCP/RTU)
- Easy to integrate with systems like Home Assistant

## Current state

Implemented today:

- Device and register configuration stored in SQLite via Ecto
- Per-device supervised connection process
- Per-register polling with custom intervals
- Parsing/scaling for common register data types (`uint16`, `int16`, `uint32`, `int32`, `float32`, `bool`)
- Delta filtering to avoid publishing unchanged values
- MQTT publish of register changes to `{base_topic}/{register_name}`
- Device topic aliases are optional, single-segment, and fall back to the device ID when omitted

In progress / next (read-first):

- Improved reconnect/retry behavior and recovery visibility
- Home Assistant discovery metadata publishing
- Operator-facing UI for managing devices and registers
- Live telemetry dashboard and freshness/status indicators

## Primary use case

1. Poll registers from a local inverter over Modbus.
2. Publish updated values quickly to MQTT.
3. Consume those values in Home Assistant sensors.
4. Keep writes deferred until read-path reliability and observability targets are met.

## Non-goals (for now)

- Cloud-managed service
- Multi-tenant SaaS scope
- Heavy historical analytics platform inside this app

## Scope decision

Current priority is read-only telemetry.

- Build and harden polling, parsing, freshness, and publish reliability first
- Leave write-oriented development (policy, guardrails, richer encoding, operator write UX) out of the runtime until the read path is fully hardened

## Architecture (high level)

1. `Engine.Bootstrapper` loads active devices/registers from DB at boot.
2. `Engine.Supervisor` starts one `DeviceSupervisor` tree per device.
3. Each device tree runs one Modbus `Connection` process and one `Poller` per register.
4. `Engine.Hub` caches latest values, filters duplicates, broadcasts internally, and publishes to MQTT.

## Run locally

Prerequisites:

- Elixir/Erlang toolchain compatible with this project
- MQTT broker reachable from your machine (defaults to localhost)

Setup and run:

1. Install dependencies and setup DB/assets:
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

The web endpoint runs at http://localhost:4000.

## Configuration

- MQTT connection is configured via `MQTT_URL` in `config/runtime.exs`.
  - Example: `mqtt://user:pass@broker.local:1883/modbus_mqtt`
- Production DB path is configured by `DATABASE_PATH`.
- Initial sample device/registers are provided in `priv/repo/seeds.exs`.

## Quality checks

Run the precommit alias before submitting changes:

```bash
mix precommit
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for phased goals and priorities.
