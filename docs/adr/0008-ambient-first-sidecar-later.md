# ADR-0008: Ambient mode first; sidecar mode later

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

The reference architecture runs OpenShift Service Mesh 3 in **ambient** mode
(no sidecars): traffic between meshed workloads is mTLS over HBONE via ztunnel,
and L7 handling needs a waypoint (**M1**, **J2**). Sidecar mode is also
supported and GA; mixing modes in one mesh is GA in 3.4 (sm:J5). The gateway
reaches the backend through the application namespace's waypoint.

## Decision

v1 targets **ambient** mode: the backend-side design uses a waypoint per
application namespace, and the `gw-only` policy and mTLS go through it (design
§6). Sidecar mode is a later story (M.13), rendering the same gateway side and
a sidecar-based `gw-only` without a waypoint.

## Consequences

- The design matches the reference deployment, so the first live validation is
  real.
- The waypoint is load-bearing: its presence (from the `Tenant` label) is a
  health check (`BackendNotMeshed`, design §12).
- A sidecar-mode customer waits for M.13; the gateway side is unchanged, only
  the backend-side wiring differs.

## Alternatives

- **Sidecar first (like the service-mesh extension's v1).** Rejected: the
  reference runs ambient, so ambient is where the first real validation is.
- **Both from day one.** Rejected: one mode proven end to end beats two
  half-proven; mixing is supported, so a later mode is additive.
