# ADR-0004: The security baseline is platform-rendered gateway policy, never a parameter

- **Status:** Proposed
- **Date:** 2026-11-16 (mechanism changed on 2026-11-17 with ADR-0003: Istio
  policies instead of Kuadrant overrides)

## Context

Today the token check, "only the gateway may call the backend" and the rate
limit are switches in each team's values file. One wrong value turns a check
off, and nothing notices. ADR-0003 builds the checks from Istio
`RequestAuthentication` and `AuthorizationPolicy` (M6, M10, M12) and two
platform-owned `EnvoyFilter`s. Istio has no layer of policy that a more
specific policy can't weaken, so the baseline must be protected by who can
write policy, not by the policy model.

## Decision

- **Every check is rendered by the platform, with the tenant gateway, in its
  namespace,** by the `api-gateway` Template (sync `strict`, so the team can't
  edit or delete it) and, per API, by the per-tenant chart:
    1. **Token floor:** `RequestAuthentication` for the platform issuer and
       audience, and an `AuthorizationPolicy` `DENY` on
       `notRequestPrincipals`: a request without a valid token from that
       issuer is refused (M6).
    1. **Default deny:** an `AuthorizationPolicy` `ALLOW` with no rules on the
       gateway: a request that no API rule allows is refused (M12).
    1. **Allowed-API rule per API:** an `ALLOW` rule scoped to the API route's
       hosts and paths, with the closed claim condition of ADR-0006 (M10).
       The rule pins the issuer: `requestPrincipals` must start with
       `<issuer>/`.
    1. **Claim headers:** `x-sub` and `x-roles` set from the token
       (`outputClaimToHeaders`), after the platform-owned header filter has
       removed any copy the caller sent (ADR-0003).
    1. **Rate limit:** the platform-owned rate limit filter; one limit per
       tier, counted per caller (ADR-0003).
- `DENY` wins over `ALLOW` in Istio, so no `ALLOW` policy, from any source,
  can let in a request without a valid platform token.
- **No security setting is a value a tenant can reach.** Issuer, audience,
  claim names, header names and tiers are bootstrap chart values, set by the
  platform for the whole cluster. The per-tenant chart has no switch for any
  of them.
- **Tenants can't write gateway policy.** Admission refuses a tenant's
  `RequestAuthentication`, `AuthorizationPolicy` or `EnvoyFilter` that targets
  or selects a tenant gateway (ADR-0008).
- A render check fails if a tenant gateway lacks any of 1–5, if an API rule is
  not closed or not scoped to its route, or if any policy names another
  issuer.

## Consequences

- A team's route can't remove a check: the checks are not on the route, and
  the team can't write gateway policy.
- An extra `ALLOW` policy written by a cluster admin could widen the
  allowed-API rule, but never past the token floor. The render check covers
  only what the charts render.
- The baseline can't differ per tenant. A tenant that needs a different issuer
  is a platform change, deliberately (G.13 if ever needed).
- The guarantee depends on admission (ADR-0008) more than the Kuadrant form
  did, because Istio has no overrides.

## Alternatives

- **Kuadrant gateway-level `overrides` (`strategy: merge`) and a listener-level
  `defaults` deny (the first version of this ADR).** Not chosen with
  ADR-0003. It would make the baseline hold even against a route-level policy
  that got through.
- **Security settings as Template parameters with safe defaults.** Rejected:
  a parameter can be set; only an absent switch can't.
- **The checks in each route's own policy.** Rejected: a route without the
  policy would serve unprotected; the default deny closes that.
- **Admission policies only.** Kept as a layer (ADR-0008), not as the
  baseline: admission checks objects, not requests.
