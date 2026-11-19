# ADR-0004: The security baseline is platform-rendered gateway policy, never a parameter

- **Status:** Proposed
- **Date:** 2026-11-16 (mechanism changed on 2026-11-17 with ADR-0003: Istio
  policies instead of Kuadrant overrides; amended the same day after an
  independent design review; on 2026-11-19, issuers per tenant and per API,
  and the rate limit exemption per API; the same day, the team's rate limit
  switch per API)

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
    1. **Token check:** `RequestAuthentication` with one rule per issuer
       that the tenant or one of its APIs uses, with its audiences, token
       only from the `Authorization` header.
    1. **Allowed-API rule per API:** an `ALLOW` scoped to the API route's
       host and path (ADR-0005), accepting only the API's issuers, with the
       closed claim condition of ADR-0006 and every mapped claim (`azp` at
       least) required (M10).
    1. **Claim headers:** `x-sub` and `x-roles` set from the token, after the
       platform-owned header filter removed any copy the caller sent
       (ADR-0003).
    1. **Rate limit:** the platform-owned rate limit filter; limits per tier,
       counted per tenant, API and caller (ADR-0003).
- `DENY` wins over `ALLOW` in Istio, so no `ALLOW` policy, from any source,
  can let in a request without a valid token from a trusted issuer.
- **Issuers are registered by the platform: one, many, one per tenant, or
  one per API.**

```yaml
auth:
  issuers:                          # every issuer the platform trusts
    shared:     { url: https://sso.example.com/realms/apis, audiences: [apis] }
    team-a:     { url: https://sso.team-a.example.com/realms/apis, audiences: [apis], tenant: team-a }
    partner-kc: { url: https://kc.partner.example.com/realms/apis, audiences: [apis], tenant: team-a }
  defaultIssuers: [shared]          # one or many, for every API that doesn't choose
  tenantIssuers:
    team-a: [team-a]                # team-a's default instead; may also name shared
```

One issuer for the cluster is one entry and the default. An issuer with
`tenant` set is run for that tenant (its own or an API's external Keycloak):
the parent refuses it in `defaultIssuers` and in another tenant's list. The
parent also refuses an unknown issuer name and two issuers with the same URL,
and skips a tenant that has no issuer; each is listed in the skipped-tenants
ConfigMap.

An API uses its tenant's default issuers, or names its own in the `api`
instance's `issuers` parameter (ADR-0005): one or more of `defaultIssuers`,
its tenant's `tenantIssuers`, and the issuers registered with its tenant. Any
other name refuses the API, with the reason in its status. So an API's
external Keycloak is trusted by that API only, not by the tenant's other
APIs.

- **No security setting is a value a tenant can reach.** Issuers and which
  tenant uses which, audiences, claim names, header names and tiers are
  bootstrap chart values, set by the platform. A team's knobs (ADR-0012) can add claim
  headers; they can't remove a platform header or touch a check.
- **One exception: the rate limit can be turned off.**
    1. **By the team, for its own API:** the `api` instance's parameter
       `rateLimit: "off"` (default `"on"`, ADR-0005), as a team turns off a
       per-API gateway's limit today. The platform can stop this for a
       tenant (`rateLimit.lockedTenants`): an `"off"` there is refused with
       the reason in the API's status, and the limit stays.
    1. **By the platform:** for a whole tenant (`rateLimit.unlimitedTenants`)
       or one API (`rateLimit.unlimitedApis`, `<tenant>.<api>`).

  The filter stays on the gateway; only the limit of that API or tenant goes.
  Every API with its limit off is listed in the tenant's status. No other
  check can be turned off.
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
  and the rate-limit exemption. An API narrows its issuers to the ones the
  platform registered for its tenant.
- A team that runs its own issuer reaches only its own tenant's APIs: no
  other tenant's gateway validates its tokens, so they get no principal and
  are refused. G.19 tests this (Q18).
- The floor accepts every trusted issuer on every gateway; the tenant's token
  check narrows it to the issuers its APIs use, and each API rule to the API's
  own. An external Keycloak can put any claim into its tokens, and still
  reaches only the APIs that name it.
- Registering an issuer changes the floor, so Istio updates every tenant
  gateway's configuration, live, with no restart. An API that starts to use
  it changes only its tenant's gateway. G.19 measures whether open
  connections are closed (Q20).
- An external Keycloak must be reachable from Istio's control plane, which
  fetches its keys about every 20 minutes. When it can't be reached, its
  tokens fail with `401`; the other issuers' tokens must keep working (Q19).
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
- **Issuers only per tenant (the version of 2026-11-19 morning).** Rejected:
  an API may bring its own Keycloak, and a tenant-wide list would let that
  Keycloak's tokens reach the tenant's other APIs.
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
- **A rate limit exemption only per tenant (the version before 2026-11-19).**
  Rejected: a tenant with several APIs may need one of them unlimited, as a
  per-API gateway can be today.
- **Only the platform turns a limit off (the version of 2026-11-19
  morning).** Rejected: teams turn their API's limit off today, and need to.
  The platform keeps control through `rateLimit.lockedTenants`.
- **A team switch honoured only for tenants the platform lists in advance.**
  Rejected: every team would need a platform change first. The platform lists
  the exceptions instead (`lockedTenants`).
