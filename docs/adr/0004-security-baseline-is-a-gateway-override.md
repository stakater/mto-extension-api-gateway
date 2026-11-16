# ADR-0004: The security baseline is a gateway-level override, never a parameter

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Today the token check, "only the gateway may call the backend" and the rate
limit are switches in each team's values file. One wrong value turns a check
off, and nothing notices. Connectivity Link policies can attach to a `Gateway`
or to an `HTTPRoute`; a gateway-level policy can declare **overrides** that a
route-level policy can't weaken, or **defaults** that a route-level policy
replaces (K6).

## Decision

- **The security baseline is a gateway-level policy with `overrides`,**
  rendered by the bootstrap chart on each tenant gateway:
    - `AuthPolicy`: a valid JWT from the platform's issuer and audience;
      `x-sub` and `x-roles` (names set by the platform) set from token claims,
      replacing anything the caller sent.
    - `RateLimitPolicy`: the platform's tiers, counted per caller.
- The override uses `strategy: merge`, so a route's own rules (its
  allowed-API rule) stay next to the baseline; the default `atomic` strategy
  would replace them (K6).
- **Deny by default.** A second policy on the gateway's listener
  (`sectionName`) holds `defaults` that refuse every request; only a
  route-level `AuthPolicy` with the allowed-API rule replaces it (ADR-0006). A
  route without that rule serves nothing (Q3). It is a second policy because
  one policy can't hold both `defaults` and `overrides` (K6).
- **No security setting is a value a tenant can reach.** Issuer, audience,
  claim names, header names and tiers are bootstrap chart values, set by the
  platform for the whole cluster. The per-tenant chart has no switch for any
  of them.
- A render check fails if a gateway-level policy is missing for a tenant
  gateway, or if any policy turns a baseline rule off.

## Consequences

- A route, a route-level policy written by hand (if RBAC ever allows one), or
  a mistake in the per-tenant chart can add a rule, never remove one.
- The baseline can't differ per tenant. A tenant that needs a different issuer
  is a platform change, deliberately (G.13 if ever needed).
- The model depends on Connectivity Link's merge semantics, which G.0 proves
  with negative tests (Q3).

## Alternatives

- **Security settings as Template parameters with safe defaults.** Rejected:
  a parameter can be set; only an absent switch can't.
- **The baseline in each route-level policy.** Rejected: a route without the
  policy would serve unprotected; overrides close that by construction.
- **Admission policies only.** Kept as defence in depth (ADR-0008), not as the
  baseline: admission checks objects, not requests.
