# ADR-0010: Telemetry through the platform collector; no second path

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

A gateway emits request metrics, access logs and spans. The platform already
runs an OpenTelemetry collector that derives the tenant from a pod's namespace
and routes telemetry to the tenant's partition through the Multi-Tenant
Operator's telemetry gateways (the Grafana/LGTM extension; sm:O3, sm:ADR-0007).
Building a second pipeline here would duplicate that and split a tenant's
telemetry across two paths.

## Decision

The gateway renders a per-gateway `Telemetry` object that sets the platform's
log format and enables tracing through the platform's collector. The extension
renders **no** collector, pipeline or telemetry gateway; a gateway's telemetry
reaches the tenant by the same path as the rest of the tenant's workloads.

## Consequences

- One telemetry path per tenant; a gateway's logs and traces land beside the
  application's.
- Telemetry wiring (collector, telemetry gateways) is an install prerequisite,
  not this extension's.
- The log format and tracing provider are install values, uniform across
  gateways.

## Alternatives

- **A dedicated gateway-telemetry pipeline.** Rejected: duplicates the platform
  collector and the Grafana extension; two paths per tenant.
- **No telemetry object; rely on defaults.** Rejected: a consistent log format
  and tracing are part of "secured and observed by default".
