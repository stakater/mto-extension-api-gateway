# ADR-0003: Istio-native policies and a few platform-owned EnvoyFilters; Kuadrant is the alternative

- **Status:** Proposed
- **Date:** 2026-11-16 (rewritten on 2026-11-17; the first version chose
  Kuadrant policies, see Alternatives)

## Context

The gateway must check the caller's token, check the allowed-API rule, set
`x-sub` and `x-roles` from the token so a caller's copy never reaches the
backend, and limit the request rate per caller and tier.

The pattern we see in practice does this with Istio `RequestAuthentication`
and `AuthorizationPolicy`, plus three hand-written `EnvoyFilter`s (header
strip, a Lua tier lookup with Envoy's rate limit filter, a correlation ID) and
an Envoy rate limit service with Redis. Red Hat lists `EnvoyFilter` as
Developer Preview in Service Mesh 3 (M2).

What we learned on 2026-11-17:

- **Istio covers the auth part with supported APIs.** `RequestAuthentication`
  and `AuthorizationPolicy` target a Gateway API `Gateway` (M6); an
  `AuthorizationPolicy` condition matches any value of a list claim, exactly
  or by prefix (M10); an `ALLOW` policy with no rules refuses everything
  (M12). Only removing a caller's header copy and the rate limit need
  `EnvoyFilter`s. Istio has no native global rate limit.
- **Kuadrant uses `EnvoyFilter`s too.** On Istio, its operator creates them on
  each gateway (K7). Upstream Kuadrant therefore does not remove the support
  problem; only Connectivity Link, which is paid, does (K1, K9).
- **Kuadrant adds several components.** The Kuadrant operator installs the
  Authorino, Limitador and DNS operators, which run Authorino and Limitador;
  every request makes a call to Authorino. A `RateLimitPolicy` reads the
  caller from an `AuthPolicy` (K10), so the rate limit can't be taken alone.
- **Hand-written filters can be tested, and the failures were our own code.**
  In a kind lab, the three filters of the pattern above applied unchanged on
  Istio 1.27.9, 1.28.10, 1.29.10 and 1.30.8. Istio did rename an internal
  route configuration in 1.28, which those filters don't match. The failures
  we found were a Lua pattern that put every caller on the lowest tier, a rate
  limit that fails open, and a list claim that reaches the backend
  base64-encoded (M11).
- The engineer who built that setup chose it over Kuadrant for the same
  reasons: fewer components, and Kuadrant's features beyond JWT and rate
  limiting are not needed.

## Decision

- **Token check and issuer:** `RequestAuthentication` on the tenant gateway
  (platform issuer, audience), and the Istio token floor: a `DENY` on
  `notRequestPrincipals` (ADR-0004).
- **Allowed-API rule:** one Istio `AuthorizationPolicy` `ALLOW` rule per API,
  scoped to the API route's hosts and paths, with the condition
  `request.auth.claims[allowed_apis]` in `api.<tenant>.<api>` or
  `api.<tenant>.<api>.*` (ADR-0006, M10). An `ALLOW` policy with no rules on
  the gateway refuses every request that no API rule allows.
- **Claim headers:** `outputClaimToHeaders` for `x-sub`; one platform-owned
  `EnvoyFilter` that removes the caller's copies of the claim headers before
  `jwt_authn` runs. `x-roles` carries the allowed-APIs claim as Istio encodes
  it (M11), and the docs say so.
- **Rate limit:** one platform-owned `EnvoyFilter` that adds Envoy's rate limit
  filter and its actions, and a rate limit service that speaks Envoy's rate
  limit API, with Redis. The tier and the caller come from token claims as
  plain values (`tier`, `azp`), read from the JWT metadata. **No Lua.**
- **Rules for every `EnvoyFilter` the extension renders:**
    - it selects exactly one tenant gateway (`workloadSelector`);
    - it matches only names Istio and Envoy document (`jwt_authn`, `router`,
      the rate limit filter), never an Istio-generated route or cluster name
      where another anchor exists;
    - it is on an allowlist in the render check, and any other
      `EnvoyFilter`, `WasmPlugin` or `TrafficExtension` fails the render;
    - the acceptance suite runs on every Service Mesh minor upgrade before a
      release says it supports that version (G.10).
- **No Kuadrant and no Connectivity Link for now** (ADR-0011).

## Consequences

- The auth path uses supported Istio APIs, inside the gateway's Envoy, with no
  extra network call.
- No extra operators. One more workload: the rate limit service and Redis.
- **Stakater owns two `EnvoyFilter`s, a Developer Preview API.** A customer
  that needs Red Hat support for every part of the gateway's request path is
  told this before it adopts the extension. The upgrade suite is the
  mitigation.
- No defaults-and-overrides model. "A tenant can't weaken the baseline" rests
  on two things: the platform renders every gateway policy (ADR-0002, sync
  `strict`), and admission refuses a tenant's `RequestAuthentication`,
  `AuthorizationPolicy` or `EnvoyFilter` that targets or selects a tenant
  gateway (ADR-0008).
- The rate limit counts per caller and tier on the tenant gateway, not per
  API. A counter per API would need a patch per route, matched on
  Istio-generated names; that is a later story if needed.
- Whether the rate limit fails open or closed when its service is down is a
  platform value, documented as a limit.
- A list claim in `x-roles` arrives base64-encoded JSON; backends decode it.

## Alternatives

- **Kuadrant policies (`AuthPolicy`, `RateLimitPolicy`), on Connectivity Link
  or upstream (the first version of this ADR).** Not chosen for now:
    - several more operators, and Authorino in every request's path;
    - Kuadrant still adds its own `EnvoyFilter`s; only Connectivity Link,
      which is paid, is supported;
    - its main gain over this decision is the rate limit, and that can't be
      taken without the auth part.

  It would give status (`Enforced`), defaults and overrides, policies per
  route, and maintained Envoy wiring. **Revisit** when a customer requires
  Red Hat support for the gateway's request path (Connectivity Link), when
  Kuadrant installs as fewer components, or when per-API rules need more than
  Istio's conditions.
- **Hand-written `EnvoyFilter`s per team (today).** Rejected: untested custom
  code per team; the Lua tier bug went unnoticed (M11).
- **Istio-native only, no rate limit.** Rejected: the rate limit is a
  requirement.
- **A separate API management product.** Rejected: out of scope (vision,
  non-goals).
