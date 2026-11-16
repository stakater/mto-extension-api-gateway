# ADR-0007: Rate limiting through the shared service, always enforced; the tier is the only knob

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

The reference architecture runs one shared Envoy rate-limit service (+ Redis)
with tiers, and every gateway calls it (**D1**, **D2**). Today the wiring is an
`EnvoyFilter`, which Istio discourages as unstable across upgrades (**D3**,
**D4**, sm:R3). Rate limiting is security-relevant: an un-limited API is a
denial-of-service and cost risk.

## Decision

- The shared rate-limit service is a **platform prerequisite** (not built here);
  its address is an install value.
- Every gateway is wired to it; there is **no parameter to disable** rate
  limiting. The `tier` parameter selects a request-rate class the platform
  defines.
- **The attachment mechanism is chosen by M.0 Q1.** If OpenShift Service Mesh
  3.4 offers a supported, stable path for a Gateway API gateway (a GA filter
  API, `HTTPRoute` filters, or a waypoint policy), use it. If not, the extension
  owns a single, well-tested `EnvoyFilter` and carries it across mesh upgrades —
  a cost accepted here explicitly, flagged in `vision.md`, and re-checked at
  each mesh release (`method.md`).

## Consequences

- No API can skip rate limiting.
- If the mechanism is an `EnvoyFilter`, the platform owns upgrade risk for it;
  that is the price of the shared-service model and is stated, not hidden.
- Tier placement (per gateway vs per consumer token) is **Q8**; v1 treats
  `tier` as a per-gateway default, with per-consumer tiering deferred (M.11).

## Alternatives

- **Rate limiting optional.** Rejected: an off switch is the footgun again
  (ADR-0002).
- **Per-gateway local rate limiting (no shared service).** Rejected for v1: it
  can't enforce a global per-consumer budget across a consumer's calls; may be a
  fallback if the shared-service attachment proves unworkable (an open decision,
  roadmap).
