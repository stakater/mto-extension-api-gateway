# ADR-0003: Kuadrant policy APIs, not EnvoyFilters

- **Status:** Proposed
- **Date:** 2026-11-16 (split on 2026-11-17: which product runs the policies
  is ADR-0011)

## Context

Today the token check is Istio `RequestAuthentication` and
`AuthorizationPolicy`; the header strip, the rate limit and the correlation ID
are `EnvoyFilter` patches, with a separate Envoy rate limit service and Redis.
An `EnvoyFilter` patches the Envoy configuration that Istio generates; when a
new Istio release generates a different configuration, the patch can stop
applying, without an error. Red Hat lists the `EnvoyFilter` API as Developer
Preview in OpenShift Service Mesh 3, and may ask a support case to be
reproduced without it (M2).

Kuadrant adds `AuthPolicy` and `RateLimitPolicy` (`kuadrant.io/v1`) to
Gateway API, on Istio gateways. Red Hat Connectivity Link is Red Hat's
supported build of Kuadrant, with the same API (K1). `AuthPolicy` checks JWTs
from an OIDC issuer such as RHBK (K2), authorizes on claim values (K3), and
sets request headers from the token (K4). `RateLimitPolicy` counts per caller
and selects limits by predicate (K5).

## Decision

- **Token check, allowed-API rule and header handling are `AuthPolicy`.**
- **Rate limits are `RateLimitPolicy`**, counted by the policy controller's
  limiter (Limitador), not by a separate Envoy rate limit service.
- **No `EnvoyFilter`, `WasmPlugin` or `TrafficExtension` in any rendered
  output.** A render check fails on any of them.
- The policy controller itself creates `EnvoyFilter`s on each gateway to load
  its filter (K7). Those are the product's managed configuration, generated
  and upgraded by its operator. The risk this ADR removes is a hand-written
  patch that nobody tests on upgrade, not the kind itself. How well that
  managed configuration is tested and supported depends on the product that
  runs it (ADR-0011).
- The policy controller is a **prerequisite**, like Service Mesh. Without its
  CRDs and a ready `Kuadrant` instance, the bootstrap chart's preflight fails
  and names it (design §8).

## Consequences

- An Istio upgrade no longer depends on a hand-written patch. The acceptance
  suite runs before and after each Service Mesh minor upgrade (AC-OPS-3).
- The rate limit tiers move into `RateLimitPolicy` objects that the platform
  owns.
- The correlation-ID patch is gone. Whether Envoy's own `x-request-id` is
  enough, or APIs need another header from a `RequestHeaderModifier` or an
  `AuthPolicy`, is open (Q11).
- One more operator to install and upgrade.
- The policy controller's behaviour on gateways whose backends run in ambient
  mode is not yet observed by us (Q1). Story G.0 confirms it.

## Alternatives

- **Keep the `EnvoyFilter`s.** Rejected: unsupported in production, and they
  break silently on upgrade — exactly when nobody looks.
- **Istio-native only (`RequestAuthentication` with `outputClaimToHeaders`,
  `AuthorizationPolicy` on the gateway, M6–M7) and no rate limit.** Kept in
  two ways: as the token floor next to the policies (ADR-0004), and as the
  fallback if G.0 finds a blocker. Alone, it covers token, allowed-API rule
  and `x-sub` without `EnvoyFilter`, but not a list claim in `x-roles` (M7),
  has no supported rate limit and no defaults-and-overrides model.
- **A separate API management product.** Rejected: out of scope (vision,
  non-goals), and it moves the gateway away from Gateway API.
