# ADR-0004: The security baseline is platform-rendered gateway policy, never a parameter

- **Status:** Proposed
- **Date:** 2026-11-16 (mechanism changed on 2026-11-17 with ADR-0003: Istio
  policies instead of Kuadrant overrides; amended the same day after an
  independent design review; issuers per tenant added on 2026-11-19)

## Context

Today the token check, "only the gateway may call the backend" and the rate
limit are switches in each team's values file. One wrong value turns a check
off, and nothing notices. ADR-0003 builds the checks from Istio
`RequestAuthentication` and `AuthorizationPolicy` (M6, M10, M12) and
platform-owned `EnvoyFilter`s. Istio has no layer of policy that a more
specific policy can't weaken, so the baseline must be protected by where the
policies live and by who can write policy, not by the policy model.

Token issuers differ. A customer runs one Keycloak per environment, and
several environments share one cluster; teams may run their own Keycloak. A
team that runs an issuer can put any claim into its tokens, including the
allowed-API claim of another tenant's API.

## Decision

- **Once per cluster, before any gateway** (bootstrap chart, Istio root
  namespace, selecting the label every tenant gateway's pods carry):
    1. **Token floor:** `DENY` on `notRequestPrincipals`, with one
       `"<issuer>/*"` per issuer the platform trusts. A request without a
       valid token from one of them is refused, whatever else exists.
    1. **Default deny:** an `ALLOW` with no rules. A request that no API rule
       allows is refused (M12).
- **Per tenant gateway** (the tenant's child `TemplateInstance`, ADR-0013):
    1. **Token check:** `RequestAuthentication` with one rule per issuer of
       the tenant and its audiences, token only from the `Authorization`
       header.
    1. **Allowed-API rule per API:** an `ALLOW` scoped to the API route's
       host and path (ADR-0005), accepting only the tenant's issuers, with the
       closed claim condition of ADR-0006 and every mapped claim (`azp` at
       least) required (M10).
    1. **Claim headers:** `x-sub` and `x-roles` set from the token, after the
       platform-owned header filter removed any copy the caller sent
       (ADR-0003).
    1. **Rate limit:** the platform-owned rate limit filter; limits per tier,
       counted per tenant and caller (ADR-0003).
- `DENY` wins over `ALLOW` in Istio, so no `ALLOW` policy, from any source,
  can let in a request without a valid token from a trusted issuer.
- **Issuers are platform values: one, many, or one per tenant.**

```yaml
auth:
  issuers:                          # every issuer the platform trusts
    shared: { url: https://sso.example.com/realms/apis, audiences: [apis] }
    team-a: { url: https://sso.team-a.example.com/realms/apis, audiences: [apis], tenant: team-a }
  defaultIssuers: [shared]          # one or many, for every tenant without its own list
  tenantIssuers:
    team-a: [team-a]                # replaces the default for team-a; may also name shared
```

One issuer for the cluster is one entry and the default. An issuer with
`tenant` set is run by that tenant: the parent refuses it in `defaultIssuers`
and in another tenant's list. The parent also refuses an unknown issuer name
and two issuers with the same URL, and skips a tenant that has no issuer;
each is listed in the skipped-tenants ConfigMap.

- **No security setting is a value a tenant can reach.** Issuers and which
  tenant uses which, audiences, claim names, header names and tiers are
  bootstrap chart values, set by the platform. A team's knobs (ADR-0012) can add claim
  headers; they can't remove a platform header or touch a check.
- **One exception, set by the platform only:** the platform may exempt a
  tenant from the rate limit (`unlimited`, per tenant in the bootstrap
  values). The filter stays; only the limit changes.
- **Tenants can't write gateway policy or act as the gateway.** Admission
  refuses a tenant's `RequestAuthentication`, `AuthorizationPolicy`,
  `Telemetry` or `EnvoyFilter` that targets or selects a tenant gateway, and a
  pod that uses a gateway's service account (ADR-0008).
- A render check fails if a tenant gateway lacks any of the per-gateway items,
  if the root-namespace `ALLOW` has any rule, if an API rule is not closed or
  not scoped to its host and path, or if a tenant's policy names an issuer
  that is not one of the tenant's.

## Consequences

- A team's route can't remove a check: the checks are not on the route, and
  the team can't write gateway policy.
- The floor and the default deny hold even while a tenant's child is being
  applied or has failed.
- An extra `ALLOW` policy written by a cluster admin could widen the
  allowed-API rule, but never past the token floor. The render check covers
  only what the charts render.
- The baseline differs per tenant only in two platform values: its issuers
  and the rate-limit exemption.
- A team that runs its own issuer reaches only its own tenant's APIs: no
  other tenant's gateway validates its tokens, so they get no principal and
  are refused. G.19 tests this (Q18).
- The floor accepts every trusted issuer on every gateway; the tenant's token
  check and API rules narrow it to the tenant's issuers.
- Every issuer must issue the same claims (`azp`, the allowed-APIs claim, the
  tier claim).
- The guarantee depends on admission (ADR-0008) more than the Kuadrant form
  did, because Istio has no overrides. Minimum admission is built before any
  API is served (G.8).

## Alternatives

- **Kuadrant gateway-level `overrides` (`strategy: merge`) and a listener-level
  `defaults` deny (the first version of this ADR).** Not chosen with
  ADR-0003. It would make the baseline hold even against a route-level policy
  that got through.
- **The floor and the default deny next to each gateway.** Rejected: they
  would protect only once applied, and only if every apply succeeded.
- **One issuer per cluster (the first version).** Rejected: one cluster
  serves several environments, each with its own Keycloak, and teams may run
  their own.
- **A floor per tenant, with only its issuers.** Rejected: a new tenant's
  floor would depend on its own render, the gap the cluster-wide floor
  closes. The tenant's token check and API rules narrow the issuers instead.
- **Security settings as Template parameters with safe defaults.** Rejected:
  a parameter can be set; only an absent switch can't.
- **The checks in each route's own policy.** Rejected: a route without the
  policy would serve unprotected; the default deny closes that.
- **Admission policies only.** Kept as a layer (ADR-0008), not as the
  baseline: admission checks objects, not requests.
