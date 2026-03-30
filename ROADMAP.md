# ROADMAP

This roadmap reflects the current project direction:

- Focus: single-device personal/home-lab bridge first
- Core objective: fast, reliable Modbus register telemetry into MQTT
- Near-term expansion: Home Assistant integration and telemetry operability
- Constraints: no cloud dependency, high stability/self-healing, extensible transports
- Scope decision: defer write-oriented features until read-path milestones are complete

## Success criteria (3-6 months)

- Home Assistant receives very fresh register updates for key telemetry points.
- Runtime behavior is resilient to temporary Modbus or broker outages.
- Operators can diagnose failures quickly from logs and system state.
- Read-path behavior is strongly covered by automated tests.

## Priority themes

1. Device management UI
2. Live telemetry dashboard
3. Reliable reconnect/retry behavior
4. Testing and quality gates

## Phase 0: Baseline hardening (now)

Goals:

- Stabilize core poll/publish loop under network faults.
- Improve observability for connection and polling paths.
- Lock in regression protection with focused tests.

Deliverables:

- Connection retry/backoff strategy for Modbus and MQTT clients.
- Structured logs with device/register context and failure reason classification.
- Integration tests for polling and delta publish behavior.
- Test fixtures for representative register data types and scaling/swap combinations.

Definition of done:

- Services recover automatically from temporary disconnects without manual restarts.
- Core read path has automated coverage for expected and failure cases.

## Phase 1: Operator controls (next)

Goals:

- Add first-class UI workflows for configuring and running the bridge.

Deliverables:

- Device management UI (CRUD for devices and registers, active/inactive control).
- Validation and guardrails for transport configuration and register definitions.
- Per-device status surfaces (connected, degraded, disconnected, last successful poll).

Definition of done:

- Common setup and maintenance can be done without direct DB edits.
- Invalid configs are blocked before runtime failures.

## Phase 2: Telemetry UX and integration

Goals:

- Improve day-to-day visibility and Home Assistant interoperability.

Deliverables:

- Live telemetry dashboard showing latest values and update recency.
- Optional stream health indicators (poll lag, read error rates, reconnect count).
- Home Assistant MQTT discovery payload support for selected entities.

Definition of done:

- Users can confirm system health and value freshness from the app UI.
- Home Assistant setup friction is reduced through discovery metadata.

## Phase 3: Write features (deferred)

Goals:

- Keep write development paused until read-first milestones are complete.

Deliverables:

- Reconfirm write requirements based on production read-only usage.
- Write policy layer (allowlist, type checks, value bounds, optional rate limits).
- Better support for non-trivial write encoding patterns where needed.
- Audit logging for write requests and outcomes.

Definition of done:

- Read-first phases are stable in production and acceptance criteria are met.
- Writable registers can then be controlled through MQTT with guardrails and traceability.

## Phase 4: Extensibility and packaging

Goals:

- Make the bridge easier to run and extend in diverse environments.

Deliverables:

- Pluggable transport contract refinements for custom/encrypted/HTTP-based transports.
- Packaging improvements (release docs, container-friendly setup, config examples).
- Expanded sample profiles for additional devices beyond the initial inverter target.

Definition of done:

- New transport adapters can be added with limited core changes.
- New users can deploy and operate the bridge with minimal guesswork.

## Open decisions

- Exact policy model for write safety (global vs per-register rules).
- Historical retention strategy (external time-series DB vs optional built-in storage).
- Preferred deployment baseline for home-lab users (native release vs containers).
