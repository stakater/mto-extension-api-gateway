# ADR-0003: Connectivity Link policies, not EnvoyFilters

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Today the token check is Istio `RequestAuthentication` and
`AuthorizationPolicy`; the header strip, the rate limit and the correlation ID
are `EnvoyFilter` patches, with a separate Envoy rate limit service and Redis.
An `EnvoyFilter` patches the Envoy configuration that Istio generates; when a
new Istio release generates a different configuration, the patch can stop
applying, without an error. Red Hat lists the `EnvoyFilter` API as Developer
Preview in OpenShift Service Mesh 3, and may ask a support case to be
reproduced without it (M2).

Red Hat Connectivity Link adds `AuthPolicy` and `RateLimitPolicy` to Gateway
API, on Service Mesh gateways, and is tested against Service Mesh releases
(K1). `AuthPolicy` checks JWTs from an OIDC issuer such as RHBK (K2),
authorizes on claim values (K3), and sets request headers from the token
(K4). `RateLimitPolicy` counts per caller and selects limits by predicate (K5).

## Decision

- **Token check, allowed-API rule and header handling are `AuthPolicy`.**
- **Rate limits are `RateLimitPolicy`**, counted by Connectivity Link's
  limiter, not by a separate Envoy rate limit service.
- **No `EnvoyFilter`, `WasmPlugin` or `TrafficExtension` in any rendered
  output.** A render check fails on any of them.
- Connectivity Link itself creates `EnvoyFilter`s on each gateway to load its
  filter (K7). Those are the product's managed configuration, generated and
  upgraded by its operator and tested by Red Hat against each Service Mesh
  release. The risk this ADR removes is a hand-written patch that nobody
  tests on upgrade, not the kind itself.
- Connectivity Link is a **prerequisite**, like Service Mesh. Without it, the
  bootstrap chart's preflight fails and names it (design §8).

## Consequences

- An Istio upgrade follows Red Hat's tested version table instead of a
  hand-written patch. The acceptance suite runs before and after each Service
  Mesh minor upgrade (AC-OPS-3).
- The rate limit tiers move into `RateLimitPolicy` objects that the platform
  owns.
- The correlation-ID patch is gone. Envoy's own `x-request-id` covers request
  correlation; a different header is a `RequestHeaderModifier` or an
  `AuthPolicy` header (Q11).
- One more Red Hat product to install, and a subscription to check (K9).
- Connectivity Link's behaviour on gateways whose backends run in ambient mode
  is not yet observed by us (Q1). Story G.0 confirms it before any chart.

## Alternatives

- **Keep the `EnvoyFilter`s.** Rejected: unsupported in production, and they
  break silently on upgrade — exactly when nobody looks.
- **Istio-native only (`RequestAuthentication` with `outputClaimToHeaders`,
  `AuthorizationPolicy` on the gateway, M6–M7) and no rate limit.** Kept as
  the fallback if G.0 finds a blocker: it covers token, allowed-API rule and
  headers without `EnvoyFilter`, but has no supported rate limit and no
  defaults-and-overrides model (ADR-0004).
- **A separate API management product.** Rejected: out of scope (vision,
  non-goals), and it moves the gateway away from Gateway API.
