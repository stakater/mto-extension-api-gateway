# ADR-0006: The allowed-API rule is derived, tenant-qualified and closed

- **Status:** Proposed
- **Date:** 2026-11-16

## Context

Today a caller may use an API if its token's allowed-APIs claim contains a
value matching a free-text pattern in the team's values, such as
`api-<team>-<api>-consumer-*`. Nothing stops `api-*` or `*`. And with `-`
joining DNS labels, names collide across tenants: tenant `team` with API
`a-orders` and tenant `team-a` with API `orders` both give
`api-team-a-orders`. `AuthPolicy` can authorize on claim values with pattern
matching or CEL (K3).

## Decision

- **The rule is derived:** the caller's allowed-APIs claim must contain a value
  that is exactly `api.<tenant>.<api>`, or starts with `api.<tenant>.<api>.`
  (for finer roles such as `api.team-a.orders.read`). The segment after the
  API name is closed by `.`, so `api.team-a.orders` never matches
  `api.team-a.orders2`.
- **`.` joins the parts.** Tenant and API names are DNS labels and contain no
  dot, so a value names exactly one tenant and one API.
- The platform may change the prefix (`api`) and the claim name, install-wide.
  It can't make the rule a wildcard: a render check fails on any pattern that
  doesn't contain both the tenant and the API name, closed.
- Existing role names in another format move with a one-time mapping in the
  identity provider (story G.9), not with a looser rule.

## Consequences

- No hand-written pattern exists, so none can be too wide.
- A caller's role names the tenant: a role for `team-b`'s `orders` never opens
  `team-a`'s `orders`.
- RHBK roles must follow the format. Creating them stays with the platform team
  for now (non-goal; G.11 automates it).

## Alternatives

- **The pattern as a parameter.** Rejected: the failure it causes (a pattern
  one character too wide) is the one we want to rule out.
- **`-` as separator, matching today's role names.** Rejected: names collide
  across tenants.
- **One role per tenant.** Rejected: every caller of one API could call all of
  the tenant's APIs.
